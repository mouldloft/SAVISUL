import AppKit

// The installer window's background, drawn at twice its size so it is sharp on Retina screens. The window is
// 720 × 440 points; Finder puts the three icons on one row, centred at x 180, 360 and 540, 206 points from the top.
let width: CGFloat = 720
let height: CGFloat = 440
let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "background.png"
let champagne = NSColor(srgbRed: 0.9, green: 0.81, blue: 0.64, alpha: 1)

guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width * 2), pixelsHigh: Int(height * 2), bitsPerSample: 8,
                                 samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                 bytesPerRow: 0, bitsPerPixel: 0) else { exit(1) }
rep.size = NSSize(width: width, height: height)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let canvas = NSRect(x: 0, y: 0, width: width, height: height)

NSGradient(colors: [NSColor(srgbRed: 0.088, green: 0.07, blue: 0.056, alpha: 1), NSColor(srgbRed: 0.04, green: 0.034, blue: 0.029, alpha: 1)])!
    .draw(in: canvas, angle: -90)
NSGradient(colors: [champagne.withAlphaComponent(0.13), champagne.withAlphaComponent(0)])!
    .draw(fromCenter: NSPoint(x: 360, y: height - 206), radius: 0, toCenter: NSPoint(x: 360, y: height - 206), radius: 300, options: [])

/// A line of text centred on the window, its top `top` points below the window's top edge.
func line(_ string: String, top: CGFloat, font: NSFont, color: NSColor, kern: CGFloat = 0) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: paragraph, .kern: kern]
    let height = ceil(font.ascender - font.descender) + 2
    (string as NSString).draw(in: NSRect(x: 0, y: canvas.height - top - height, width: canvas.width, height: height), withAttributes: attributes)
}

func serifItalic(_ size: CGFloat) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: .regular).fontDescriptor
    let serif = base.withDesign(.serif) ?? base
    return NSFont(descriptor: serif.withSymbolicTraits(.italic), size: size) ?? NSFont.systemFont(ofSize: size)
}

line("SAVISUL", top: 44, font: NSFont.systemFont(ofSize: 30, weight: .heavy), color: NSColor.white.withAlphaComponent(0.96), kern: 3.2)
line("установка в один шаг", top: 84, font: serifItalic(17), color: champagne)

// A fine arrow from the app to the installer, centred between their icons.
let y = height - 206
let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: 240, y: y))
arrow.line(to: NSPoint(x: 299, y: y))
arrow.move(to: NSPoint(x: 292, y: y + 6))
arrow.line(to: NSPoint(x: 300, y: y))
arrow.line(to: NSPoint(x: 292, y: y - 6))
arrow.lineWidth = 1.4
arrow.lineCapStyle = .round
arrow.lineJoinStyle = .round
champagne.withAlphaComponent(0.75).setStroke()
arrow.stroke()

let rule = NSBezierPath()
rule.move(to: NSPoint(x: 300, y: 64))
rule.line(to: NSPoint(x: 420, y: 64))
rule.lineWidth = 0.5
champagne.withAlphaComponent(0.3).setStroke()
rule.stroke()
line("Дальше SAVISUL обновляется сам", top: 388, font: NSFont.systemFont(ofSize: 12, weight: .medium), color: NSColor.white.withAlphaComponent(0.5))

NSGraphicsContext.restoreGraphicsState()
guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
do {
    try png.write(to: URL(fileURLWithPath: output))
} catch {
    exit(1)
}
