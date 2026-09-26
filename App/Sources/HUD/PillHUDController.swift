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
import Combine
import SwiftUI
import VoiceIQCore

/// Owns the non-activating NSPanel that hosts the pill. Fixed-size panel; the pill
/// animates its own bounds inside (avoids NSWindow frame-animation jank).
/// The panel never becomes key except transiently for the locked-state stop button.
@MainActor
final class PillHUDController {
    let model = PillModel()
    private let panel: NSPanel
    private var stateObservation: AnyCancellable?
    private var eventMonitors: [Any] = []
    private var mouseMonitor: Any?

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 96),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.acceptsMouseMovedEvents = true
        panel.contentView = NSHostingView(
            rootView: PillRootView(model: model)
        )
        stateObservation = model.$state.sink { [weak self] state in
            self?.updatePanel(for: state)
        }
        reposition()
    }

    func show() {
        reposition()
        panel.orderFrontRegardless()
        followMouse()
    }

    /// Called at each session start so the pill follows the display the user is
    /// actually dictating on (audit L14 — it used to stick to the launch screen).
    func repositionToActiveScreen() {
        reposition()
    }

    func hide() {
        stopFollowingMouse()
        panel.orderOut(nil)
    }

    /// While the pill is up it lives on whichever display the pointer is on.
    /// People dictate into one screen and glance at another to read from it;
    /// the pill goes with the glance so the live text is never behind them.
    private func followMouse() {
        guard mouseMonitor == nil else { return }
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in
            guard let self, let screen = Self.screenUnderMouse(),
                  screen.frame != self.panel.screen?.frame else { return }
            self.place(on: screen)
        }
    }

    private func stopFollowingMouse() {
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        mouseMonitor = nil
    }

    private func updatePanel(for state: PillState) {
        let isAnswer: Bool
        if case .answer = state { isAnswer = true } else { isAnswer = false }
        let size = isAnswer ? answerPanelSize() : NSSize(width: 600, height: 96)
        let oldOrigin = panel.frame.origin
        panel.setFrame(NSRect(origin: oldOrigin, size: size), display: true, animate: panel.isVisible)
        reposition()
        isAnswer ? installAnswerMonitors() : removeAnswerMonitors()
    }

    private func answerPanelSize() -> NSSize {
        let visible = targetScreen()?.visibleFrame.size ?? NSSize(width: 600, height: 320)
        return NSSize(width: min(560, visible.width - 24), height: min(300, visible.height - 24))
    }

    private func installAnswerMonitors() {
        guard eventMonitors.isEmpty else { return }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown], handler: { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown, event.keyCode == 53 {
                self.dismissAnswer()
                return nil
            }
            if event.type != .keyDown, event.window != self.panel {
                self.dismissAnswer()
            }
            return event
        }) {
            eventMonitors.append(local)
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown], handler: { [weak self] event in
            if event.type == .keyDown, event.keyCode != 53 { return }
            self?.dismissAnswer()
        }) {
            eventMonitors.append(global)
        }
    }

    private func removeAnswerMonitors() {
        eventMonitors.forEach(NSEvent.removeMonitor)
        eventMonitors.removeAll()
    }

    private func dismissAnswer() {
        NotificationCenter.default.post(name: .pillAnswerDismissed, object: nil)
    }

    private func reposition() {
        guard let screen = targetScreen() else { return }
        place(on: screen)
    }

    /// Bottom-center of `screen`.
    private func place(on screen: NSScreen) {
        let frame = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(
            x: frame.midX - panel.frame.width / 2,
            y: frame.minY + 16
        ))
    }

    /// The display under the pointer, which is where the eyes are. The screen
    /// hosting the focused window is only a fallback for when the pointer is
    /// off every display (mid-drag between screens, headless remote session).
    private func targetScreen() -> NSScreen? {
        Self.screenUnderMouse() ?? Self.screenOfFocusedWindow() ?? NSScreen.main
    }

    private static func screenUnderMouse() -> NSScreen? {
        let point = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(point) })
    }

    /// Screen hosting the frontmost app's front window, via the window list —
    /// a local syscall, never an AX round-trip into the target app. The AX
    /// version could block ~100ms per attribute on a busy app, and this runs
    /// on the key-press path where the pill must appear instantly (dogfood).
    private static func screenOfFocusedWindow() -> NSScreen? {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        // The list is front-to-back; the first normal-layer window owned by the
        // frontmost app is its focused/front window.
        guard let info = windows.first(where: {
            ($0[kCGWindowOwnerPID as String] as? pid_t) == pid
                && (($0[kCGWindowLayer as String] as? Int) ?? 1) == 0
        }), let bounds = info[kCGWindowBounds as String] as? [String: CGFloat] else {
            return nil
        }
        let midX = (bounds["X"] ?? 0) + (bounds["Width"] ?? 0) / 2
        let midY = (bounds["Y"] ?? 0) + (bounds["Height"] ?? 0) / 2
        // Window-list coords are top-left-origin global; flip into Cocoa space.
        guard let primary = NSScreen.screens.first else { return nil }
        let cocoaPoint = NSPoint(x: midX, y: primary.frame.maxY - midY)
        return NSScreen.screens.first(where: { $0.frame.contains(cocoaPoint) })
    }
}

private struct PillRootView: View {
    @ObservedObject var model: PillModel

    var body: some View {
        VStack {
            Spacer(minLength: 0)
            PillView(model: model)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, 8)
    }
}
