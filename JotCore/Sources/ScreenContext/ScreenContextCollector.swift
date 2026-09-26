// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import AppKit
import CoreGraphics
import Foundation
import ScreenCaptureKit

@MainActor
public final class ScreenContextCollector {
    public private(set) var images: [Data] = []

    private let maxImages: Int
    private let maxDimension: CGFloat
    private let jpegQuality: CGFloat
    private var activationObserver: NSObjectProtocol?
    private var debounceTask: Task<Void, Never>?
    private var isRunning = false

    public init(maxImages: Int = 4, maxDimension: CGFloat = 1280, jpegQuality: CGFloat = 0.6) {
        self.maxImages = max(1, maxImages)
        self.maxDimension = max(1, maxDimension)
        self.jpegQuality = min(1, max(0, jpegQuality))
    }

    public func start() {
        guard !isRunning else { return }
        images = []
        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
            Log.screen.info("screen context unavailable because Screen Recording access was denied")
            return
        }

        isRunning = true
        capture()
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication else { return }
            Task { @MainActor [weak self] in
                guard let self, application.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
                self.debounceTask?.cancel()
                self.debounceTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    guard !Task.isCancelled else { return }
                    self?.capture()
                }
            }
        }
    }

    public func stop() -> [Data] {
        isRunning = false
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
            self.activationObserver = nil
        }
        debounceTask?.cancel()
        debounceTask = nil
        return images
    }

    private func capture() {
        guard isRunning else { return }
        let displayID = Self.frontmostDisplay()?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
            .flatMap { $0 as? NSNumber }
            .map { CGDirectDisplayID($0.uint32Value) } ?? CGMainDisplayID()
        let maxDimension = maxDimension
        let jpegQuality = jpegQuality

        Task { [weak self] in
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard !Task.isCancelled,
                      let display = content.displays.first(where: { $0.displayID == displayID })
                        ?? content.displays.first else { return }
                let scale = min(1, maxDimension / CGFloat(max(display.width, display.height)))
                let configuration = SCStreamConfiguration()
                configuration.width = max(1, Int(CGFloat(display.width) * scale))
                configuration.height = max(1, Int(CGFloat(display.height) * scale))
                configuration.showsCursor = false
                let image = try await SCScreenshotManager.captureImage(
                    contentFilter: SCContentFilter(display: display, excludingWindows: []),
                    configuration: configuration
                )
                guard !Task.isCancelled else { return }
                let data = await Task.detached(priority: .utility) {
                    let bitmap = NSBitmapImageRep(cgImage: image)
                    return bitmap.representation(
                        using: .jpeg,
                        properties: [.compressionFactor: jpegQuality]
                    )
                }.value
                guard let self, self.isRunning, let data else { return }
                self.append(data)
            } catch is CancellationError {
            } catch {
                Log.screen.info("screen context capture failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    private func append(_ image: Data) {
        if images.count >= maxImages {
            images.remove(at: images.count == 1 ? 0 : 1)
        }
        images.append(image)
    }

    private static func frontmostDisplay() -> NSScreen? {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                        kCGNullWindowID) as? [[String: Any]],
              let bounds = windows.first(where: {
                  ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid
                      && ($0[kCGWindowLayer as String] as? NSNumber)?.intValue == 0
              })?[kCGWindowBounds as String] as? [String: CGFloat],
              let x = bounds["X"], let y = bounds["Y"],
              let width = bounds["Width"], let height = bounds["Height"] else {
            return NSScreen.main
        }
        let center = CGPoint(x: x + width / 2, y: y + height / 2)
        let desktopTop = NSScreen.screens.map(\.frame.maxY).max() ?? 0
        let appKitCenter = CGPoint(x: center.x, y: desktopTop - center.y)
        return NSScreen.screens.first(where: { $0.frame.contains(appKitCenter) }) ?? NSScreen.main
    }
}
