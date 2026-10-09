import AppKit

let width = 680
let height = 440
let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "background.png"

let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
    let background = NSGradient(colors: [
        NSColor(srgbRed: 0.13, green: 0.12, blue: 0.11, alpha: 1),
        NSColor(srgbRed: 0.08, green: 0.08, blue: 0.09, alpha: 1)
    ])!
    background.draw(in: rect, angle: 90)

    func draw(_ text: String, at point: NSPoint, size: CGFloat, weight: NSFont.Weight, alpha: CGFloat, align: NSTextAlignment = .left) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = align
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: NSColor.white.withAlphaComponent(alpha),
            .paragraphStyle: paragraph
        ]
        let boxX: CGFloat = align == .center ? 36 : point.x
        let boxWidth: CGFloat = align == .center ? rect.width - 72 : rect.width - point.x - 36
        let box = NSRect(x: boxX, y: point.y, width: boxWidth, height: size + 10)
        (text as NSString).draw(in: box, withAttributes: attributes)
    }

    draw("SAVISUL", at: NSPoint(x: 36, y: height - 58), size: 26, weight: .semibold, alpha: 0.94)
    draw("Слева приложение  ·  справа установщик",
         at: NSPoint(x: 36, y: height - 86), size: 14, weight: .medium, alpha: 0.62)
    draw("→", at: NSPoint(x: 36, y: 228), size: 32, weight: .regular, alpha: 0.9, align: .center)

    draw("Если пишет «не был открыт» — откройте «Если не открывается»",
         at: NSPoint(x: 36, y: 58), size: 12, weight: .medium, alpha: 0.58)
    draw("и вставьте весь текст в Терминал. Mac с чипом Apple, macOS 14 или новее.",
         at: NSPoint(x: 36, y: 38), size: 12, weight: .regular, alpha: 0.42)
    return true
}

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fputs("Could not render the installer background.\n", stderr)
    exit(1)
}
do {
    try png.write(to: URL(fileURLWithPath: output))
} catch {
    fputs("\(error)\n", stderr)
    exit(1)
}
