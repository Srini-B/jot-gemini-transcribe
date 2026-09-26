#!/usr/bin/env swift

import AppKit
import CoreGraphics
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let brandURL = root.appendingPathComponent(".amp/in/brand")
let resourcesURL = root.appendingPathComponent("App/Resources")
let artifactsURL = root.appendingPathComponent(".amp/in/artifacts")
let fileManager = FileManager.default

func load(_ name: String) -> CGImage {
    let url = brandURL.appendingPathComponent(name)
    guard let image = NSImage(contentsOf: url),
          let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        fatalError("Could not load \(url.path)")
    }
    return cgImage
}

func bitmap(width: Int, height: Int, draw: (CGContext, CGRect) -> Void) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: width, height: height)
    let context = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
    context.interpolationQuality = .high
    draw(context, CGRect(x: 0, y: 0, width: width, height: height))
    context.flush()
    return rep
}

func writePNG(_ rep: NSBitmapImageRep, to url: URL) throws {
    try rep.representation(using: .png, properties: [:])!.write(to: url)
}

func alphaBounds(_ image: CGImage) -> CGRect {
    let rep = NSBitmapImageRep(cgImage: image)
    var minX = image.width, minY = image.height, maxX = -1, maxY = -1
    for y in 0..<image.height {
        for x in 0..<image.width where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.01 {
            minX = min(minX, x); minY = min(minY, y)
            maxX = max(maxX, x); maxY = max(maxY, y)
        }
    }
    guard maxX >= minX else { fatalError("Image has no visible pixels") }
    return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
}

func fitted(content: CGSize, in canvas: CGRect, fraction: CGFloat = 1) -> CGRect {
    let available = CGSize(width: canvas.width * fraction, height: canvas.height * fraction)
    let scale = min(available.width / content.width, available.height / content.height)
    let size = CGSize(width: content.width * scale, height: content.height * scale)
    return CGRect(x: canvas.midX - size.width / 2, y: canvas.midY - size.height / 2,
                  width: size.width, height: size.height)
}

let logo = load("voiceiq-logo.png")
let favicon = load("voiceiq-fav.png")
let logoRep = NSBitmapImageRep(cgImage: logo)
let logoBounds = alphaBounds(logo)

var regions: [Range<Int>] = []
var regionStart = Int(logoBounds.minX)
var transparentRun = 0
for x in Int(logoBounds.minX)...Int(logoBounds.maxX) {
    var visible = false
    for y in Int(logoBounds.minY)...Int(logoBounds.maxY) where (logoRep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.01 {
        visible = true
        break
    }
    transparentRun = visible ? 0 : transparentRun + 1
    if transparentRun == 24 {
        let gapStart = x - transparentRun + 1
        if gapStart > regionStart { regions.append(regionStart..<gapStart) }
        regionStart = x + 1
    }
}
if regionStart <= Int(logoBounds.maxX) { regions.append(regionStart..<(Int(logoBounds.maxX) + 1)) }
guard let markRegion = regions.last else { fatalError("Could not isolate the logo mark") }
let markRect = CGRect(x: markRegion.lowerBound, y: Int(logoBounds.minY),
                      width: markRegion.count, height: Int(logoBounds.height)).integral
guard let mark = logo.cropping(to: markRect) else { fatalError("Could not crop logo mark") }

var navy = NSColor(deviceRed: 0.04, green: 0.07, blue: 0.16, alpha: 1)
var darkest = CGFloat.greatestFiniteMagnitude
for y in Int(markRect.minY)..<Int(markRect.maxY) {
    for x in Int(markRect.minX)..<Int(markRect.maxX) {
        guard let color = logoRep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB), color.alphaComponent > 0.8 else { continue }
        let luminance = color.redComponent * 0.2126 + color.greenComponent * 0.7152 + color.blueComponent * 0.0722
        if luminance > 0.02, luminance < darkest {
            darkest = luminance
            navy = NSColor(deviceRed: color.redComponent, green: color.greenComponent, blue: color.blueComponent, alpha: 1)
        }
    }
}

try fileManager.createDirectory(at: resourcesURL, withIntermediateDirectories: true)
try fileManager.createDirectory(at: artifactsURL, withIntermediateDirectories: true)
let iconset = fileManager.temporaryDirectory.appendingPathComponent("VoiceIQ-\(UUID().uuidString).iconset")
try fileManager.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? fileManager.removeItem(at: iconset) }

// The favicon is the light-on-dark rendering of the mark (white face and
// headphone ring, blue sparkles, transparent head), so it goes straight onto
// the logo's navy. The navy-on-dark crop from the wordmark has no contrast.
let favBounds = alphaBounds(favicon)
guard let favCrop = favicon.cropping(to: favBounds) else { fatalError("Could not crop favicon") }

for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        let rep = bitmap(width: pixels, height: pixels) { context, canvas in
            let rounded = CGPath(roundedRect: canvas, cornerWidth: canvas.width * 0.225,
                                 cornerHeight: canvas.height * 0.225, transform: nil)
            context.addPath(rounded)
            context.setFillColor(navy.cgColor)
            context.fillPath()
            context.saveGState()
            context.addPath(rounded)
            context.clip()
            context.draw(favCrop, in: fitted(content: CGSize(width: favCrop.width, height: favCrop.height), in: canvas, fraction: 0.68))
            context.restoreGState()
        }
        let suffix = scale == 2 ? "@2x" : ""
        try writePNG(rep, to: iconset.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"))
        if pixels == 512 { try writePNG(rep, to: artifactsURL.appendingPathComponent("app-icon-512.png")) }
    }
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", resourcesURL.appendingPathComponent("VoiceIQ.icns").path]
try iconutil.run(); iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed") }

for scale in [1, 2] {
    let pixels = 18 * scale
    let rep = bitmap(width: pixels, height: pixels) { context, canvas in
        context.draw(favCrop, in: fitted(content: CGSize(width: favCrop.width, height: favCrop.height), in: canvas, fraction: 0.94))
        context.setBlendMode(.sourceIn)
        context.setFillColor(NSColor.black.cgColor)
        context.fill(canvas)
    }
    try writePNG(rep, to: resourcesURL.appendingPathComponent(scale == 1 ? "MenuBarIcon.png" : "MenuBarIcon@2x.png"))
}

func sidebarImage(height: Int, dark: Bool) -> NSBitmapImageRep {
    let width = Int((CGFloat(height) * logoBounds.width / logoBounds.height).rounded(.up))
    guard let crop = logo.cropping(to: logoBounds) else { fatalError("Could not crop wordmark") }
    let regular = bitmap(width: width, height: height) { $0.draw(crop, in: $1) }
    guard dark else { return regular }
    let source = NSBitmapImageRep(data: regular.representation(using: .png, properties: [:])!)!
    let transformed = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    for y in 0..<height {
        for x in 0..<width {
            guard let color = source.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB), color.alphaComponent > 0 else { continue }
            let isBlue = color.blueComponent > 0.4 && color.blueComponent > color.redComponent * 1.25
                && color.blueComponent > color.greenComponent * 1.08
            let output = isBlue
                ? NSColor(deviceRed: color.redComponent, green: color.greenComponent,
                          blue: color.blueComponent, alpha: color.alphaComponent)
                : NSColor(deviceRed: 1, green: 1, blue: 1, alpha: color.alphaComponent)
            transformed.setColor(output, atX: x, y: y)
        }
    }
    return transformed
}

for (height, suffix) in [(28, ""), (56, "@2x")] {
    try writePNG(sidebarImage(height: height, dark: false), to: resourcesURL.appendingPathComponent("SidebarLogo\(suffix).png"))
    try writePNG(sidebarImage(height: height, dark: true), to: resourcesURL.appendingPathComponent("SidebarLogoDark\(suffix).png"))
}

let menu = NSImage(contentsOf: resourcesURL.appendingPathComponent("MenuBarIcon@2x.png"))!
for (name, background, foreground) in [
    ("menubar-light.png", NSColor(deviceWhite: 0.94, alpha: 1), NSColor.black),
    ("menubar-dark.png", NSColor(deviceWhite: 0.12, alpha: 1), NSColor.white),
] {
    let rep = bitmap(width: 72, height: 72) { context, canvas in
        context.setFillColor(background.cgColor); context.fill(canvas)
        let iconRect = CGRect(x: 18, y: 18, width: 36, height: 36)
        context.saveGState()
        context.setFillColor(foreground.cgColor)
        context.clip(to: iconRect, mask: menu.cgImage(forProposedRect: nil, context: nil, hints: nil)!)
        context.fill(iconRect)
        context.restoreGState()
    }
    try writePNG(rep, to: artifactsURL.appendingPathComponent(name))
}

print("Wrote app, menu bar, and sidebar icons. Mark crop: \(markRect). Navy: \(navy)")
