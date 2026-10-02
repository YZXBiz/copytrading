// Renders the 1024 px master for Resources/AppIcon.icns.
// Usage: swift app/scripts/render_app_icon.swift <output.png>
// Then: app/scripts/build_app_icon.sh regenerates the .icns from it.

import AppKit
import CoreGraphics

let size: CGFloat = 1024
// Apple's macOS icon grid: an 824 pt body centered on a 1024 pt canvas.
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let cornerRadius: CGFloat = 185

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

func gradient(_ colors: [CGColor], _ locations: [CGFloat]) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: colors as CFArray, locations: locations)!
}

let space = CGColorSpace(name: CGColorSpace.sRGB)!
let context = CGContext(
    data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
)!

let squircle = CGPath(roundedRect: body, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

// Drop shadow under the body, as on system icons.
context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: color(0x000000, 0.35))
context.addPath(squircle)
context.setFillColor(color(0x0A1224))
context.fillPath()
context.restoreGState()

// Body: deep navy fading to indigo, with a teal glow rising from the lower right.
context.saveGState()
context.addPath(squircle)
context.clip()
context.drawLinearGradient(
    gradient([color(0x1B2B5E), color(0x0B1430)], [0, 1]),
    start: CGPoint(x: body.minX, y: body.maxY), end: CGPoint(x: body.maxX, y: body.minY), options: []
)
context.drawRadialGradient(
    gradient([color(0x19C6B0, 0.45), color(0x19C6B0, 0)], [0, 1]),
    startCenter: CGPoint(x: 760, y: 300), startRadius: 0,
    endCenter: CGPoint(x: 760, y: 300), endRadius: 520, options: []
)

// Faint chart grid.
context.setStrokeColor(color(0xFFFFFF, 0.07))
context.setLineWidth(3)
for step in 1..<6 {
    let offset = body.minX + CGFloat(step) * body.width / 6
    context.move(to: CGPoint(x: offset, y: body.minY))
    context.addLine(to: CGPoint(x: offset, y: body.maxY))
    context.move(to: CGPoint(x: body.minX, y: offset))
    context.addLine(to: CGPoint(x: body.maxX, y: offset))
}
context.strokePath()

// The signal: a flat line that spikes like a pulse, then breaks out upward.
let points: [CGPoint] = [
    CGPoint(x: 215, y: 430),
    CGPoint(x: 330, y: 430),
    CGPoint(x: 395, y: 560),
    CGPoint(x: 470, y: 300),
    CGPoint(x: 545, y: 470),
    CGPoint(x: 610, y: 430),
    CGPoint(x: 740, y: 600),
]
let tip = CGPoint(x: 800, y: 680)
let signal = CGMutablePath()
signal.move(to: points[0])
for point in points.dropFirst() { signal.addLine(to: point) }
signal.addLine(to: tip)

func strokeSignal(width: CGFloat) {
    context.saveGState()
    context.addPath(signal)
    context.setLineWidth(width)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.replacePathWithStrokedPath()
    context.clip()
    context.drawLinearGradient(
        gradient([color(0x4FA8FF), color(0x3CF2C9)], [0, 1]),
        start: CGPoint(x: 215, y: 0), end: CGPoint(x: 800, y: 0), options: []
    )
    context.restoreGState()
}

// Soft glow first, drawn as a blurred shadow of a solid stroke so it brightens rather than outlines.
context.saveGState()
context.setShadow(offset: .zero, blur: 46, color: color(0x3CF2C9, 0.75))
context.addPath(signal)
context.setLineWidth(30)
context.setLineCap(.round)
context.setLineJoin(.round)
context.setStrokeColor(color(0x2ED3C0, 0.9))
context.strokePath()
context.restoreGState()
strokeSignal(width: 40)

// Endpoint: a bright node with a halo, where the signal becomes a trade.
for (radius, alpha) in [(92.0, 0.12), (64.0, 0.22)] {
    context.setFillColor(color(0x3CF2C9, alpha))
    context.fillEllipse(in: CGRect(x: tip.x - radius, y: tip.y - radius, width: radius * 2, height: radius * 2))
}
context.saveGState()
context.setShadow(offset: .zero, blur: 30, color: color(0x3CF2C9, 0.9))
context.setFillColor(color(0xE9FFFA))
context.fillEllipse(in: CGRect(x: tip.x - 40, y: tip.y - 40, width: 80, height: 80))
context.restoreGState()

// Top sheen, like the glass highlight on system icons.
context.drawLinearGradient(
    gradient([color(0xFFFFFF, 0.14), color(0xFFFFFF, 0)], [0, 1]),
    start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: body.midY + 80), options: []
)
context.restoreGState()

// Hairline edge so the icon holds its shape on dark backgrounds.
context.addPath(squircle.copy(using: nil)!)
context.setStrokeColor(color(0xFFFFFF, 0.12))
context.setLineWidth(3)
context.strokePath()

let image = context.makeImage()!
let output = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png")
let rep = NSBitmapImageRep(cgImage: image)
try rep.representation(using: .png, properties: [:])!.write(to: output)
