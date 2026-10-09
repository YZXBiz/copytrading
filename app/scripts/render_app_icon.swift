// Renders the 1024 px master for Resources/AppIcon.icns.
// Usage: swift app/scripts/render_app_icon.swift <output.png>
// Then: app/scripts/build_app_icon.sh regenerates the .icns from it.
//
// The icon is two ink circles on a white sheet: an outlined ring, the guru's call, and a solid
// disc overlapping it, your copy of that call. Black on white, nothing else.

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
let radius: CGFloat = 178
let centerY: CGFloat = 512
let call = CGPoint(x: 512 - 104, y: centerY)
let copy = CGPoint(x: 512 + 104, y: centerY)

// The guru's call: a ring.
context.setStrokeColor(ink)
context.setLineWidth(30)
context.strokeEllipse(in: CGRect(x: call.x - radius, y: call.y - radius, width: radius * 2, height: radius * 2))

// Your copy: the same circle, solid, a step to the right, with a thin white gap where it covers
// the ring so the two read as separate shapes.
let gap: CGFloat = 16
context.setFillColor(color(0xFFFFFF))
context.fillEllipse(in: CGRect(x: copy.x - radius - gap, y: copy.y - radius - gap, width: (radius + gap) * 2, height: (radius + gap) * 2))
context.setFillColor(ink)
context.fillEllipse(in: CGRect(x: copy.x - radius, y: copy.y - radius, width: radius * 2, height: radius * 2))

let image = context.makeImage()!
let rep = NSBitmapImageRep(cgImage: image)
let url = URL(fileURLWithPath: CommandLine.arguments[1])
try rep.representation(using: .png, properties: [:])!.write(to: url)
