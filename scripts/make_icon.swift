import AppKit
import Foundation

// Builds the macOS .iconset from the supplied cat artwork (assets/…png), masked
// into a rounded-square tile with a soft drop shadow. If the artwork is missing,
// falls back to a simple vector cat so the build still succeeds.
//
// Usage: swift make_icon.swift <output.iconset> [sourceImage.png]

let args = Array(CommandLine.arguments.dropFirst())
let output = args.first ?? "AppIcon.iconset"
let sourcePath = args.count > 1 ? args[1] : nil
let outputURL = URL(fileURLWithPath: output)
try? FileManager.default.removeItem(at: outputURL)
try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

let sizes: [(String, CGFloat)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024)
]

let sourceImage: NSImage? = sourcePath.flatMap { NSImage(contentsOfFile: $0) }

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let ctx = NSGraphicsContext.current!
    ctx.imageInterpolation = .high

    let inset = size * 0.06
    let tileRect = NSRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
    let radius = tileRect.width * 0.2237
    let tile = NSBezierPath(roundedRect: tileRect, xRadius: radius, yRadius: radius)

    // Soft drop shadow so the tile reads as a floating macOS icon.
    ctx.saveGraphicsState()
    let drop = NSShadow()
    drop.shadowColor = NSColor.black.withAlphaComponent(0.45)
    drop.shadowBlurRadius = size * 0.03
    drop.shadowOffset = NSSize(width: 0, height: -size * 0.012)
    drop.set()
    NSColor(calibratedWhite: 0.03, alpha: 1).setFill()
    tile.fill()
    ctx.restoreGraphicsState()

    ctx.saveGraphicsState()
    tile.addClip()
    if let src = sourceImage {
        src.draw(in: tileRect, from: .zero, operation: .sourceOver, fraction: 1)
    } else {
        // Fallback: near-black tile + simple glowing cat silhouette.
        NSColor(calibratedWhite: 0.04, alpha: 1).setFill()
        tile.fill()
        let s = tileRect.width
        func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: tileRect.minX + x * s, y: tileRect.minY + y * s) }
        let cat = NSBezierPath()
        cat.move(to: p(0.50, 0.16)); cat.line(to: p(0.78, 0.42)); cat.line(to: p(0.71, 0.86))
        cat.line(to: p(0.57, 0.57)); cat.line(to: p(0.43, 0.57)); cat.line(to: p(0.29, 0.86))
        cat.line(to: p(0.22, 0.42)); cat.close()
        NSColor.black.setFill(); cat.fill()
        let glow = NSShadow(); glow.shadowColor = NSColor.white.withAlphaComponent(0.85); glow.shadowBlurRadius = size * 0.02; glow.set()
        NSColor.white.setStroke(); cat.lineWidth = max(1, size * 0.012); cat.lineJoinStyle = .round; cat.stroke()
    }
    ctx.restoreGraphicsState()

    image.unlockFocus()
    return image
}

if sourceImage == nil { FileHandle.standardError.write("make_icon: source artwork not found, using vector fallback\n".data(using: .utf8)!) }

for (name, size) in sizes {
    let image = drawIcon(size: size)
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("Unable to render icon \(name)")
    }
    try png.write(to: outputURL.appendingPathComponent(name))
}
