import AppKit
import Foundation

guard CommandLine.arguments.count > 1 else {
    fputs("Usage: swift generate-dmg-background.swift <output.png>\n", stderr)
    exit(1)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let size = NSSize(width: 900, height: 540)
let image = NSImage(size: size)

image.lockFocus()

let rect = NSRect(origin: .zero, size: size)
let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 1.0, green: 0.95, blue: 0.70, alpha: 1.0),
    NSColor(calibratedRed: 1.0, green: 0.88, blue: 0.40, alpha: 1.0)
])
gradient?.draw(in: rect, angle: -90)

let title = "Drag Screeny to Applications"
let attrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 52, weight: .bold),
    .foregroundColor: NSColor.black.withAlphaComponent(0.85)
]
let titleSize = title.size(withAttributes: attrs)
let titleRect = NSRect(x: (size.width - titleSize.width) / 2, y: size.height - titleSize.height - 70, width: titleSize.width, height: titleSize.height)
title.draw(in: titleRect, withAttributes: attrs)

let subtitle = "Signed build • Launch once after install to enable auto-start"
let subAttrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 20, weight: .medium),
    .foregroundColor: NSColor.black.withAlphaComponent(0.7)
]
let subSize = subtitle.size(withAttributes: subAttrs)
let subRect = NSRect(x: (size.width - subSize.width) / 2, y: titleRect.minY - 36, width: subSize.width, height: subSize.height)
subtitle.draw(in: subRect, withAttributes: subAttrs)

image.unlockFocus()

guard
    let tiff = image.tiffRepresentation,
    let rep = NSBitmapImageRep(data: tiff),
    let png = rep.representation(using: .png, properties: [:])
else {
    fputs("Failed to generate image data\n", stderr)
    exit(1)
}

try png.write(to: outputURL)
print("Generated DMG background: \(outputURL.path)")
