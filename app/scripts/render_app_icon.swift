// Renders the 1024 px master for Resources/AppIcon.icns.
// Usage: swift app/scripts/render_app_icon.swift <output.png>
// Then: app/scripts/build_app_icon.sh regenerates the .icns from it.
//
// The icon is the app's own drawing: a white sheet with one ink line, drawn by hand, that dips,
// holds, and rises to a solid dot where a call becomes a trade. Black on white, nothing else.

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

let space = CGColorSpace(name: CGColorSpace.sRGB)!
let context = CGContext(
    data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
)!

let squircle = CGPath(roundedRect: body, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

// A soft shadow under the sheet, as on system icons.
context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -8), blur: 24, color: color(0x000000, 0.22))
context.addPath(squircle)
context.setFillColor(color(0xFFFFFF))
context.fillPath()
context.restoreGState()

// The sheet: paper white, with the faintest warmth toward the bottom.
context.saveGState()
context.addPath(squircle)
context.clip()
context.drawLinearGradient(
    CGGradient(colorsSpace: space, colors: [color(0xFFFFFF), color(0xF4F3F0)] as CFArray, locations: [0, 1])!,
    start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: body.minY), options: []
)
context.restoreGState()
context.addPath(squircle)
context.setStrokeColor(color(0x000000, 0.08))
context.setLineWidth(2)
context.strokePath()

let ink = color(0x1D1F21)

// The ground: nearly level, with the wobble of a line drawn without a ruler.
let ground = CGMutablePath()
ground.move(to: CGPoint(x: 230, y: 300))
ground.addCurve(to: CGPoint(x: 512, y: 296), control1: CGPoint(x: 320, y: 304), control2: CGPoint(x: 420, y: 292))
ground.addCurve(to: CGPoint(x: 794, y: 302), control1: CGPoint(x: 610, y: 300), control2: CGPoint(x: 700, y: 306))
context.addPath(ground)
context.setStrokeColor(color(0x1D1F21, 0.28))
context.setLineWidth(14)
context.setLineCap(.round)
context.strokePath()

// The line: it dips, holds, and rises, the shape of a good copied trade.
let line = CGMutablePath()
line.move(to: CGPoint(x: 236, y: 470))
line.addCurve(to: CGPoint(x: 400, y: 420), control1: CGPoint(x: 300, y: 470), control2: CGPoint(x: 340, y: 404))
line.addCurve(to: CGPoint(x: 540, y: 520), control1: CGPoint(x: 460, y: 436), control2: CGPoint(x: 480, y: 530))
line.addCurve(to: CGPoint(x: 744, y: 712), control1: CGPoint(x: 620, y: 508), control2: CGPoint(x: 660, y: 690))
context.addPath(line)
context.setStrokeColor(ink)
context.setLineWidth(34)
context.setLineCap(.round)
context.setLineJoin(.round)
context.strokePath()

// The dot where the line arrives: the trade.
let dot: CGFloat = 46
context.setFillColor(ink)
context.fillEllipse(in: CGRect(x: 744 - dot, y: 712 - dot, width: dot * 2, height: dot * 2))

let image = context.makeImage()!
let rep = NSBitmapImageRep(cgImage: image)
let url = URL(fileURLWithPath: CommandLine.arguments[1])
try rep.representation(using: .png, properties: [:])!.write(to: url)
