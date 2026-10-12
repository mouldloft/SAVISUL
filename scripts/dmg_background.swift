import AppKit

// The installer window's background, drawn at twice its size so it is sharp on Retina screens.
// Three icons sit on one row 200 points apart (centres at x 160, 360 and 560, y 214 from the top); this draws
// the title above them, the arrow between the app and the installer, a caption under each, and a footer.
let width: CGFloat = 720
let height: CGFloat = 460
let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "background.png"
let champagne = NSColor(srgbRed: 0.90, green: 0.81, blue: 0.64, alpha: 1)

guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width * 2), pixelsHigh: Int(height * 2), bitsPerSample: 8,
                                 samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                 bytesPerRow: 0, bitsPerPixel: 0) else { exit(1) }
rep.size = NSSize(width: width, height: height)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let canvas = NSRect(x: 0, y: 0, width: width, height: height)

NSGradient(colors: [NSColor(srgbRed: 0.095, green: 0.075, blue: 0.06, alpha: 1), NSColor(srgbRed: 0.045, green: 0.038, blue: 0.032, alpha: 1)])!
    .draw(in: canvas, angle: -90)
NSGradient(colors: [champagne.withAlphaComponent(0.16), champagne.withAlphaComponent(0)])!
    .draw(fromCenter: NSPoint(x: 360, y: 250), radius: 0, toCenter: NSPoint(x: 360, y: 250), radius: 330, options: [])

/// Text centred on x, with its top `top` points below the window's top edge.
func text(_ string: String, x: CGFloat, top: CGFloat, size: CGFloat, weight: NSFont.Weight, color: NSColor, kern: CGFloat = 0, width box: CGFloat = 220) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color,
                                                     .paragraphStyle: paragraph, .kern: kern]
    (string as NSString).draw(in: NSRect(x: x - box / 2, y: height - top - size * 1.4, width: box, height: size * 1.4), withAttributes: attributes)
}

text("SAVISUL", x: 360, top: 40, size: 30, weight: .semibold, color: NSColor.white.withAlphaComponent(0.95), kern: 7, width: 400)
text("Установка в один шаг", x: 360, top: 84, size: 13, weight: .medium, color: champagne.withAlphaComponent(0.85), width: 400)

// The arrow from the app to the installer, between the two icons.
let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: 226, y: height - 214))
arrow.line(to: NSPoint(x: 294, y: height - 214))
arrow.move(to: NSPoint(x: 286, y: height - 207))
arrow.line(to: NSPoint(x: 295, y: height - 214))
arrow.line(to: NSPoint(x: 286, y: height - 221))
arrow.lineWidth = 1.6
arrow.lineCapStyle = .round
arrow.lineJoinStyle = .round
champagne.withAlphaComponent(0.8).setStroke()
arrow.stroke()

for (x, caption) in [(CGFloat(160), "Приложение"), (360, "Нажмите дважды — и готово"), (560, "Если macOS не даёт открыть")] {
    text(caption, x: x, top: 300, size: 11.5, weight: .regular, color: NSColor.white.withAlphaComponent(0.46), width: 190)
}

let rule = NSBezierPath()
rule.move(to: NSPoint(x: 220, y: height - 372))
rule.line(to: NSPoint(x: 500, y: height - 372))
rule.lineWidth = 0.5
NSColor.white.withAlphaComponent(0.1).setStroke()
rule.stroke()
text("Дальше SAVISUL обновляется сам: Настройки → Обновления", x: 360, top: 388, size: 12, weight: .medium,
     color: NSColor.white.withAlphaComponent(0.62), width: 520)
text("Mac с чипом Apple · macOS 14.2 или новее", x: 360, top: 410, size: 11, weight: .regular,
     color: NSColor.white.withAlphaComponent(0.36), width: 520)

NSGraphicsContext.restoreGraphicsState()
guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
do {
    try png.write(to: URL(fileURLWithPath: output))
} catch {
    fputs("\(error)\n", stderr)
    exit(1)
}
