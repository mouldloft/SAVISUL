import AppKit
import SwiftUI

/// The four-block SAVISUL mark, taken from the granite cabinet front.
enum Mark {
    static func rects(in rect: CGRect) -> [CGRect] {
        let gap = max(1.5, rect.width * 0.055)
        let leftWidth = rect.width * 0.28
        let middleWidth = rect.width * 0.12
        let rightOffset = leftWidth + gap + middleWidth + gap
        let rightWidth = max(1, rect.width - rightOffset)
        let half = max(1, (rect.height - gap) / 2)
        return [
            CGRect(x: rect.minX, y: rect.minY, width: leftWidth, height: rect.height),
            CGRect(x: rect.minX + leftWidth + gap, y: rect.minY, width: middleWidth, height: rect.height),
            CGRect(x: rect.minX + rightOffset, y: rect.minY, width: rightWidth, height: half),
            CGRect(x: rect.minX + rightOffset, y: rect.minY + half + gap, width: rightWidth, height: half)
        ]
    }

    static func statusImage(awake: Bool, recording: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 20, height: 16), flipped: false) { _ in
            (recording ? NSColor.labelColor : NSColor.black).setFill()
            for block in rects(in: CGRect(x: 1.5, y: 3.5, width: 17, height: 10)) {
                NSBezierPath(roundedRect: block, xRadius: 0.8, yRadius: 0.8).fill()
            }
            if awake {
                NSBezierPath(roundedRect: CGRect(x: 1.5, y: 0.6, width: 17, height: 1.5), xRadius: 0.75, yRadius: 0.75).fill()
            }
            if recording {
                NSColor.systemRed.setFill()
                NSBezierPath(ovalIn: CGRect(x: 13.5, y: 9.5, width: 6.5, height: 6.5)).fill()
            }
            return true
        }
        image.isTemplate = !recording
        image.accessibilityDescription = "SAVISUL"
        return image
    }

    static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

struct StoneMark: View {
    var color: Color = Palette.ink

    var body: some View {
        Canvas { context, size in
            for block in Mark.rects(in: CGRect(origin: .zero, size: size)) {
                let radius = min(block.width, block.height) * 0.14
                context.fill(Path(roundedRect: block, cornerRadius: radius), with: .color(color))
            }
        }
        .accessibilityHidden(true)
    }
}

/// Renders the Dock icon: ivory mark on polished, gold-flecked granite.
@MainActor
enum IconRenderer {
    /// Geometry in 1024-point icon space.
    struct Slab {
        var inset: CGFloat = 100
        var radius: CGFloat = 186
        var mark: CGFloat = 500
        var shadow = true
        var flecks = 520
    }

    /// Browser icons crop the slab tighter and enlarge the mark so it still reads at 16 px.
    static func writeExtensionIcons(to folder: URL) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let specs: [(Int, Slab)] = [
            (16, Slab(inset: 0, radius: 230, mark: 780, shadow: false, flecks: 0)),
            (32, Slab(inset: 16, radius: 220, mark: 720, shadow: false, flecks: 0)),
            (48, Slab(inset: 48, radius: 210, mark: 620, shadow: false, flecks: 200)),
            (128, Slab(inset: 64, radius: 200, mark: 560, shadow: true, flecks: 520))
        ]
        for (pixels, slab) in specs {
            guard let bitmap = render(pixels: pixels, slab: slab),
                  let data = bitmap.representation(using: .png, properties: [:]) else { continue }
            try? data.write(to: folder.appendingPathComponent("icon\(pixels).png"))
        }
    }

    static func writeIconset(to folder: URL) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let specs: [(String, Int)] = [
            ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
            ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
            ("icon_512x512", 512), ("icon_512x512@2x", 1024)
        ]
        for (name, pixels) in specs {
            guard let bitmap = render(pixels: pixels),
                  let data = bitmap.representation(using: .png, properties: [:]) else { continue }
            try? data.write(to: folder.appendingPathComponent("\(name).png"))
        }
    }

    static func render(pixels: Int, slab: Slab = Slab()) -> NSBitmapImageRep? {
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .calibratedRGB,
            bytesPerRow: 0, bitsPerPixel: 0),
            let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        bitmap.size = NSSize(width: pixels, height: pixels)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        draw(scale: CGFloat(pixels) / 1024, geometry: slab)
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        return bitmap
    }

    private static func draw(scale s: CGFloat, geometry: Slab) {
        let side = (1024 - geometry.inset * 2) * s
        let body = NSRect(x: geometry.inset * s, y: geometry.inset * s, width: side, height: side)
        let radius = geometry.radius * s
        let slab = NSBezierPath(roundedRect: body, xRadius: radius, yRadius: radius)

        if geometry.shadow {
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.38)
            shadow.shadowBlurRadius = 26 * s
            shadow.shadowOffset = NSSize(width: 0, height: -12 * s)
            shadow.set()
            NSColor.black.setFill()
            slab.fill()
            NSGraphicsContext.restoreGraphicsState()
        }

        NSGraphicsContext.saveGraphicsState()
        slab.addClip()
        NSGradient(colors: [
            NSColor(calibratedRed: 0.2, green: 0.19, blue: 0.18, alpha: 1),
            NSColor(calibratedRed: 0.045, green: 0.043, blue: 0.04, alpha: 1)
        ])?.draw(in: body, angle: -90)

        var random = SeededRandom(seed: 0x5A71_5011)
        for _ in 0..<geometry.flecks {
            let x = body.minX + CGFloat(random.next()) * body.width
            let y = body.minY + CGFloat(random.next()) * body.height
            let size = (0.8 + CGFloat(random.next()) * 2.4) * s
            let gold = random.next() > 0.68
            let color = gold
                ? NSColor(calibratedRed: 0.84, green: 0.73, blue: 0.52, alpha: 0.42)
                : NSColor(white: 1, alpha: 0.09)
            color.setFill()
            NSBezierPath(ovalIn: NSRect(x: x, y: y, width: size, height: size)).fill()
        }

        let sheen = NSBezierPath()
        sheen.move(to: NSPoint(x: body.minX, y: body.maxY))
        sheen.line(to: NSPoint(x: body.minX + body.width * 0.66, y: body.maxY))
        sheen.line(to: NSPoint(x: body.minX, y: body.minY + body.height * 0.36))
        sheen.close()
        NSGradient(colors: [NSColor(white: 1, alpha: 0.15), NSColor(white: 1, alpha: 0)])?.draw(in: sheen, angle: -50)
        NSGraphicsContext.restoreGraphicsState()

        let markSize = NSSize(width: geometry.mark * s, height: geometry.mark * 0.6 * s)
        let markRect = NSRect(x: 512 * s - markSize.width / 2, y: 512 * s - markSize.height / 2,
                              width: markSize.width, height: markSize.height)
        let ivory = NSGradient(colors: [
            NSColor(calibratedRed: 0.99, green: 0.97, blue: 0.93, alpha: 1),
            NSColor(calibratedRed: 0.83, green: 0.76, blue: 0.64, alpha: 1)
        ])
        let corner = 12 * geometry.mark / 500 * s
        for block in Mark.rects(in: markRect) {
            ivory?.draw(in: NSBezierPath(roundedRect: block, xRadius: corner, yRadius: corner), angle: -90)
        }

        let rim = NSBezierPath(roundedRect: body.insetBy(dx: 2 * s, dy: 2 * s), xRadius: radius - 2 * s, yRadius: radius - 2 * s)
        rim.lineWidth = 3 * s
        NSColor(white: 1, alpha: 0.13).setStroke()
        rim.stroke()
    }
}

struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> Double {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Double(state >> 11) / Double(1 << 53)
    }
}
