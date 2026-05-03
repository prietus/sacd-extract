#!/usr/bin/env swift
import AppKit
import CoreGraphics

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
    let ctx = NSGraphicsContext.current!.cgContext

    // Squircle background with blue gradient
    let radius: CGFloat = 228
    let bgPath = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.saveGState()
    ctx.addPath(bgPath)
    ctx.clip()

    let colors = [
        CGColor(srgbRed: 0.24, green: 0.42, blue: 0.82, alpha: 1),
        CGColor(srgbRed: 0.08, green: 0.13, blue: 0.30, alpha: 1),
        CGColor(srgbRed: 0.04, green: 0.06, blue: 0.15, alpha: 1)
    ] as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.6, 1])!
    ctx.drawLinearGradient(gradient,
                           start: CGPoint(x: 0, y: size),
                           end: CGPoint(x: size, y: 0),
                           options: [])

    // Subtle top highlight
    let highlightColors = [
        CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.12),
        CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0)
    ] as CFArray
    let highlight = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: highlightColors, locations: [0, 1])!
    ctx.drawLinearGradient(highlight,
                           start: CGPoint(x: size/2, y: size),
                           end: CGPoint(x: size/2, y: size * 0.55),
                           options: [])

    ctx.restoreGState()

    // SACD disc
    let center = CGPoint(x: size/2, y: size/2)
    let outerR: CGFloat = size * 0.36

    // Disc body with radial gradient (dark, metallic)
    ctx.saveGState()
    ctx.addArc(center: center, radius: outerR, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    ctx.clip()
    let discColors = [
        CGColor(srgbRed: 0.15, green: 0.18, blue: 0.28, alpha: 1),
        CGColor(srgbRed: 0.03, green: 0.04, blue: 0.08, alpha: 1)
    ] as CFArray
    let discGrad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: discColors, locations: [0, 1])!
    ctx.drawRadialGradient(discGrad,
                           startCenter: CGPoint(x: center.x - outerR * 0.25, y: center.y + outerR * 0.25),
                           startRadius: 0,
                           endCenter: center,
                           endRadius: outerR,
                           options: [])
    ctx.restoreGState()

    // Iridescent grooves (concentric light rings)
    ctx.setLineWidth(1.2)
    for i in stride(from: 0, to: 40, by: 1) {
        let r = outerR - CGFloat(i) * (outerR * 0.02) - 4
        if r < outerR * 0.25 { break }
        let hue = (CGFloat(i) * 0.025).truncatingRemainder(dividingBy: 1)
        let ringColor = NSColor(calibratedHue: hue, saturation: 0.25, brightness: 0.9, alpha: 0.08)
        ctx.setStrokeColor(ringColor.cgColor)
        ctx.addArc(center: center, radius: r, startAngle: 0, endAngle: .pi * 2, clockwise: false)
        ctx.strokePath()
    }

    // Outer rim (subtle bright ring)
    ctx.setStrokeColor(NSColor(white: 1, alpha: 0.22).cgColor)
    ctx.setLineWidth(3)
    ctx.addArc(center: center, radius: outerR, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    ctx.strokePath()

    // Inner label ring
    let labelR: CGFloat = outerR * 0.40
    ctx.setFillColor(CGColor(srgbRed: 0.10, green: 0.13, blue: 0.22, alpha: 1))
    ctx.addArc(center: center, radius: labelR, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    ctx.fillPath()
    ctx.setStrokeColor(NSColor(white: 1, alpha: 0.15).cgColor)
    ctx.setLineWidth(2)
    ctx.addArc(center: center, radius: labelR, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    ctx.strokePath()

    // Center spindle hole
    let holeR: CGFloat = outerR * 0.08
    ctx.setFillColor(CGColor(srgbRed: 0.02, green: 0.02, blue: 0.04, alpha: 1))
    ctx.addArc(center: center, radius: holeR, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    ctx.fillPath()

    // Subtle rainbow reflection arc (top-left)
    ctx.saveGState()
    ctx.addArc(center: center, radius: outerR, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    ctx.clip()
    let rainbowColors: [CGColor] = [
        NSColor.systemPink.withAlphaComponent(0).cgColor,
        NSColor.systemOrange.withAlphaComponent(0.2).cgColor,
        NSColor.systemYellow.withAlphaComponent(0.22).cgColor,
        NSColor.systemGreen.withAlphaComponent(0.2).cgColor,
        NSColor.systemTeal.withAlphaComponent(0.22).cgColor,
        NSColor.systemPurple.withAlphaComponent(0).cgColor
    ]
    let rainbow = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: rainbowColors as CFArray, locations: [0, 0.2, 0.4, 0.6, 0.8, 1])!
    ctx.setBlendMode(.screen)
    ctx.drawLinearGradient(rainbow,
                           start: CGPoint(x: center.x - outerR, y: center.y + outerR),
                           end: CGPoint(x: center.x + outerR * 0.3, y: center.y - outerR * 0.3),
                           options: [])
    ctx.restoreGState()

    return true
}

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let data = rep.representation(using: .png, properties: [:]) else {
    print("Failed to encode PNG"); exit(1)
}

let out = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "icon_1024.png")
try data.write(to: out)
print("Wrote \(out.path) (\(data.count / 1024) KB)")
