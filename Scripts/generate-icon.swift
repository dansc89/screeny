import AppKit
import Foundation

let outputPath = CommandLine.arguments.dropFirst().first ?? "Resources/AppIcon.icns"
let outputURL = URL(fileURLWithPath: outputPath)
let iconsetURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("screeny-icon-\(UUID().uuidString).iconset", isDirectory: true)

let specs: [(name: String, size: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    guard let ctx = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }

    ctx.setShouldAntialias(true)
    ctx.setAllowsAntialiasing(true)

    NSColor.clear.setFill()
    NSBezierPath(rect: NSRect(x: 0, y: 0, width: size, height: size)).fill()

    let pad = size * 0.07
    let bgRect = NSRect(x: pad, y: pad, width: size - (pad * 2), height: size - (pad * 2))
    let bgRadius = size * 0.22
    NSColor(calibratedRed: 1.0, green: 0.84, blue: 0.16, alpha: 1.0).setFill()
    NSBezierPath(roundedRect: bgRect, xRadius: bgRadius, yRadius: bgRadius).fill()

    // Round eyeball core
    let eyeDiameter = size * 0.64
    let eyeRect = NSRect(
        x: (size - eyeDiameter) / 2,
        y: (size - eyeDiameter) / 2,
        width: eyeDiameter,
        height: eyeDiameter
    )

    let eye = NSBezierPath(ovalIn: eyeRect)
    NSColor.white.setFill()
    eye.fill()
    eye.lineWidth = max(1.0, size * 0.022)
    NSColor.black.withAlphaComponent(0.95).setStroke()
    eye.stroke()

    // Slightly off-center iris to feel "staring"
    let irisDiameter = eyeDiameter * 0.82
    let irisRect = NSRect(
        x: eyeRect.midX - irisDiameter * 0.5 + eyeDiameter * 0.03,
        y: eyeRect.midY - irisDiameter * 0.5 + eyeDiameter * 0.02,
        width: irisDiameter,
        height: irisDiameter
    )

    let iris = NSBezierPath(ovalIn: irisRect)
    NSColor(calibratedRed: 0.22, green: 0.66, blue: 0.92, alpha: 1.0).setFill()
    iris.fill()

    iris.lineWidth = max(1.0, size * 0.012)
    NSColor.black.withAlphaComponent(0.4).setStroke()
    iris.stroke()

    // Super dilated pupil
    let pupilDiameter = irisDiameter * 0.86
    let pupilRect = NSRect(
        x: irisRect.midX - pupilDiameter / 2,
        y: irisRect.midY - pupilDiameter / 2,
        width: pupilDiameter,
        height: pupilDiameter
    )
    NSColor.black.setFill()
    NSBezierPath(ovalIn: pupilRect).fill()

    // Eye highlight
    let shineDiameter = pupilDiameter * 0.24
    let shineRect = NSRect(
        x: pupilRect.minX + pupilDiameter * 0.2,
        y: pupilRect.maxY - pupilDiameter * 0.3,
        width: shineDiameter,
        height: shineDiameter
    )
    NSColor.white.withAlphaComponent(0.9).setFill()
    NSBezierPath(ovalIn: shineRect).fill()

    image.unlockFocus()
    return image
}

func pngData(from image: NSImage) -> Data? {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff) else {
        return nil
    }

    return rep.representation(using: .png, properties: [.compressionFactor: 1.0])
}

do {
    try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

    for spec in specs {
        let image = drawIcon(size: CGFloat(spec.size))
        guard let data = pngData(from: image) else {
            throw NSError(domain: "ScreenyIcon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode \(spec.name)"])
        }
        try data.write(to: iconsetURL.appendingPathComponent(spec.name), options: .atomic)
    }

    try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)

    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    task.arguments = ["-c", "icns", iconsetURL.path, "-o", outputURL.path]
    try task.run()
    task.waitUntilExit()

    if task.terminationStatus != 0 {
        throw NSError(domain: "ScreenyIcon", code: Int(task.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "iconutil failed"])
    }

    print("Generated icon: \(outputURL.path)")
    try? FileManager.default.removeItem(at: iconsetURL)
} catch {
    fputs("Error: \(error.localizedDescription)\n", stderr)
    exit(1)
}
