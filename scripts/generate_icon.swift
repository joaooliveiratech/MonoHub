import AppKit
import CoreGraphics
import Foundation

let colorSpace = CGColorSpaceCreateDeviceRGB()

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1.0) -> CGColor {
    NSColor(red: r, green: g, blue: b, alpha: a).cgColor
}

func renderMaster(size: Int) -> CGImage {
    let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

    guard let ctx = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: bitmapInfo.rawValue
    ) else {
        fatalError("Failed to create CGContext")
    }

    let scale = CGFloat(size) / 1024.0
    func s(_ val: CGFloat) -> CGFloat { val * scale }
    func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
        CGRect(x: s(x), y: s(y), width: s(w), height: s(h))
    }

    // 1. macOS Squircle Path
    let squircleRect = rect(52, 52, 920, 920)
    let cornerRadius = s(210)
    let squirclePath = CGPath(roundedRect: squircleRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

    // Outer Shadow
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s(24)), blur: s(36), color: color(0, 0, 0, 0.55))
    ctx.addPath(squirclePath)
    ctx.setFillColor(color(0.06, 0.08, 0.12))
    ctx.fillPath()
    ctx.restoreGState()

    // Base Squircle Clipping
    ctx.saveGState()
    ctx.addPath(squirclePath)
    ctx.clip()

    // Deep Obsidian / Midnight Sapphire Gradient Background
    let bgColors = [
        color(0.09, 0.14, 0.22),
        color(0.04, 0.06, 0.10)
    ] as CFArray
    let bgGrad = CGGradient(colorsSpace: colorSpace, colors: bgColors, locations: [0.0, 1.0])!
    ctx.drawLinearGradient(bgGrad, start: CGPoint(x: s(512), y: s(972)), end: CGPoint(x: s(512), y: s(52)), options: [])

    // Subtle Orbital Hub Rings
    ctx.setStrokeColor(color(0.18, 0.38, 0.55, 0.28))
    ctx.setLineWidth(s(2.5))
    let center = CGPoint(x: s(512), y: s(512))
    for radius in [s(370), s(270)] {
        ctx.strokeEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    }

    // 2x2 Modular Hub Tiles
    let tileSize = s(230)
    let gap = s(36)
    let leftX = s(512) - gap / 2 - tileSize
    let rightX = s(512) + gap / 2
    let bottomY = s(512) - gap / 2 - tileSize
    let topY = s(512) + gap / 2
    let tileRadius = s(54)

    let tiles: [(CGRect, (CGFloat, CGFloat, CGFloat), (CGFloat, CGFloat, CGFloat))] = [
        // Top-Left: Telemetry / CPU (Cyan -> Blue)
        (CGRect(x: leftX, y: topY, width: tileSize, height: tileSize), (0.0, 0.85, 0.95), (0.05, 0.45, 0.90)),
        // Top-Right: Clean / Sparkle (Teal -> Emerald)
        (CGRect(x: rightX, y: topY, width: tileSize, height: tileSize), (0.10, 0.95, 0.75), (0.05, 0.65, 0.55)),
        // Bottom-Left: Disk / Purge (Indigo -> Purple)
        (CGRect(x: leftX, y: bottomY, width: tileSize, height: tileSize), (0.45, 0.45, 1.0), (0.30, 0.25, 0.85)),
        // Bottom-Right: Power / Bolt (Amber -> Orange)
        (CGRect(x: rightX, y: bottomY, width: tileSize, height: tileSize), (1.0, 0.75, 0.20), (0.95, 0.45, 0.15))
    ]

    for (rect, c1, c2) in tiles {
        ctx.saveGState()
        let path = CGPath(roundedRect: rect, cornerWidth: tileRadius, cornerHeight: tileRadius, transform: nil)
        ctx.setShadow(offset: CGSize(width: 0, height: -s(10)), blur: s(20), color: color(c1.0, c1.1, c1.2, 0.35))
        ctx.addPath(path)
        ctx.clip()

        let gradColors = [
            color(c1.0, c1.1, c1.2, 0.92),
            color(c2.0, c2.1, c2.2, 0.88)
        ] as CFArray
        let grad = CGGradient(colorsSpace: colorSpace, colors: gradColors, locations: [0.0, 1.0])!
        ctx.drawLinearGradient(grad, start: CGPoint(x: rect.minX, y: rect.maxY), end: CGPoint(x: rect.maxX, y: rect.minY), options: [])

        ctx.setStrokeColor(color(1, 1, 1, 0.35))
        ctx.setLineWidth(s(4))
        ctx.addPath(path)
        ctx.strokePath()
        ctx.restoreGState()
    }

    // Glyph 1 (Top-Left): Pulse Waveform (Stats)
    ctx.saveGState()
    let wave = CGMutablePath()
    let tlX = leftX
    let tlY = topY + tileSize / 2
    wave.move(to: CGPoint(x: tlX + s(38), y: tlY))
    wave.addLine(to: CGPoint(x: tlX + s(78), y: tlY))
    wave.addLine(to: CGPoint(x: tlX + s(100), y: tlY + s(52)))
    wave.addLine(to: CGPoint(x: tlX + s(128), y: tlY - s(52)))
    wave.addLine(to: CGPoint(x: tlX + s(152), y: tlY + s(28)))
    wave.addLine(to: CGPoint(x: tlX + s(170), y: tlY))
    wave.addLine(to: CGPoint(x: tlX + s(192), y: tlY))
    ctx.addPath(wave)
    ctx.setStrokeColor(color(1, 1, 1, 0.95))
    ctx.setLineWidth(s(14))
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.strokePath()
    ctx.restoreGState()

    // Glyph 2 (Top-Right): 4-Point Sparkle Star (Clean)
    func drawSparkle(center: CGPoint, radius: CGFloat) {
        ctx.saveGState()
        let sp = CGMutablePath()
        sp.move(to: CGPoint(x: center.x, y: center.y - radius))
        sp.addQuadCurve(to: CGPoint(x: center.x + radius, y: center.y), control: center)
        sp.addQuadCurve(to: CGPoint(x: center.x, y: center.y + radius), control: center)
        sp.addQuadCurve(to: CGPoint(x: center.x - radius, y: center.y), control: center)
        sp.addQuadCurve(to: CGPoint(x: center.x, y: center.y - radius), control: center)
        sp.closeSubpath()
        ctx.addPath(sp)
        ctx.setFillColor(color(1, 1, 1, 0.95))
        ctx.fillPath()
        ctx.restoreGState()
    }
    drawSparkle(center: CGPoint(x: rightX + tileSize * 0.46, y: topY + tileSize * 0.48), radius: s(64))
    drawSparkle(center: CGPoint(x: rightX + tileSize * 0.74, y: topY + tileSize * 0.72), radius: s(28))

    // Glyph 3 (Bottom-Left): Storage Gauge Ring
    ctx.saveGState()
    let blCenter = CGPoint(x: leftX + tileSize / 2, y: bottomY + tileSize / 2)
    ctx.setStrokeColor(color(1, 1, 1, 0.30))
    ctx.setLineWidth(s(18))
    ctx.strokeEllipse(in: CGRect(x: blCenter.x - s(56), y: blCenter.y - s(56), width: s(112), height: s(112)))
    ctx.setStrokeColor(color(1, 1, 1, 0.95))
    ctx.setLineCap(.round)
    ctx.addArc(center: blCenter, radius: s(56), startAngle: .pi * 0.2, endAngle: .pi * 1.65, clockwise: false)
    ctx.strokePath()
    ctx.restoreGState()

    // Glyph 4 (Bottom-Right): Lightning Bolt (Optimization & Power)
    ctx.saveGState()
    let brX = rightX + tileSize / 2
    let brY = bottomY + tileSize / 2
    let bolt = CGMutablePath()
    bolt.move(to: CGPoint(x: brX + s(12), y: brY + s(68)))
    bolt.addLine(to: CGPoint(x: brX - s(42), y: brY - s(6)))
    bolt.addLine(to: CGPoint(x: brX + s(4), y: brY - s(6)))
    bolt.addLine(to: CGPoint(x: brX - s(12), y: brY - s(68)))
    bolt.addLine(to: CGPoint(x: brX + s(42), y: brY + s(6)))
    bolt.addLine(to: CGPoint(x: brX - s(4), y: brY + s(6)))
    bolt.closeSubpath()
    ctx.addPath(bolt)
    ctx.setFillColor(color(1, 1, 1, 0.95))
    ctx.fillPath()
    ctx.restoreGState()

    // Border bevel highlight
    ctx.setStrokeColor(color(1.0, 1.0, 1.0, 0.16))
    ctx.setLineWidth(s(3))
    ctx.addPath(squirclePath)
    ctx.strokePath()

    ctx.restoreGState()

    guard let img = ctx.makeImage() else {
        fatalError("Failed to makeImage")
    }
    return img
}

func main() {
    let fileManager = FileManager.default
    let iconsetDir = "Resources/AppIcon.iconset"
    try? fileManager.removeItem(atPath: iconsetDir)
    try! fileManager.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)

    let sizes: [(String, Int)] = [
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

    for (name, size) in sizes {
        let img = renderMaster(size: size)
        let url = URL(fileURLWithPath: "\(iconsetDir)/\(name)")
        let rep = NSBitmapImageRep(cgImage: img)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            fatalError("Failed png representation for \(name)")
        }
        try! data.write(to: url)
    }
    print("Iconset generated in \(iconsetDir)")
}

main()
