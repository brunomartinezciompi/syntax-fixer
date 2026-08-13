// Generates the iconset PNGs (run from build.sh; not part of the app).
import AppKit

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."

func drawIcon(pixels: Int) -> Data {
    let size = CGFloat(pixels)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    ) else { fatalError("could not create the bitmap") }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // Icon body: macOS-style margin + rounded corners.
    let inset = size * 0.055
    let body = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let radius = size * 0.225
    let shape = NSBezierPath(roundedRect: body, xRadius: radius, yRadius: radius)

    // Subtle gradient so it doesn't look flat.
    NSGradient(
        starting: NSColor(red: 0.129, green: 0.129, blue: 0.149, alpha: 1),
        ending: NSColor(red: 0.043, green: 0.043, blue: 0.055, alpha: 1)
    )?.draw(in: shape, angle: -90)

    // Light inner border: adds depth against dark backgrounds.
    shape.lineWidth = max(1, size * 0.006)
    NSColor(red: 1, green: 1, blue: 1, alpha: 0.10).setStroke()
    shape.stroke()

    // The prompt chevron, centered on the glyph's real outline: a monospace
    // advance width leaves asymmetric padding and it shows in the icon.
    let glyphSize = size * 0.44
    let font = NSFont.monospacedSystemFont(ofSize: glyphSize, weight: .bold)
    let text = NSAttributedString(string: "❯", attributes: [
        .font: font,
        .foregroundColor: NSColor(red: 0.412, green: 0.827, blue: 0.588, alpha: 1),
    ])
    if let context = NSGraphicsContext.current?.cgContext {
        let line = CTLineCreateWithAttributedString(text)
        let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        context.textPosition = CGPoint(
            x: (size - bounds.width) / 2 - bounds.minX,
            y: (size - bounds.height) / 2 - bounds.minY
        )
        CTLineDraw(line, context)
    }

    NSGraphicsContext.restoreGraphicsState()

    guard let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("could not encode the PNG")
    }
    return data
}

// Names iconutil expects.
let variants: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

for (name, pixels) in variants {
    let url = URL(fileURLWithPath: outDir).appendingPathComponent("\(name).png")
    try drawIcon(pixels: pixels).write(to: url)
}
print("✓ iconset generated")
