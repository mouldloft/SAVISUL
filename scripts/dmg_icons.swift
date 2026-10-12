import AppKit

// Gives the installer's two helper files icons in SAVISUL's style instead of Terminal's script icon and a plain text
// page, so the three icons in the window read as one set. Usage: dmg_icons <install command> <help text>
func icon(_ symbol: String) -> NSImage {
    let side: CGFloat = 1024
    return NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
        let plate = NSBezierPath(roundedRect: rect.insetBy(dx: 100, dy: 100), xRadius: 186, yRadius: 186)
        NSGraphicsContext.current?.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.45)
        shadow.shadowBlurRadius = 36
        shadow.shadowOffset = NSSize(width: 0, height: -18)
        shadow.set()
        NSColor(srgbRed: 0.11, green: 0.09, blue: 0.075, alpha: 1).setFill()
        plate.fill()
        NSGraphicsContext.current?.restoreGraphicsState()
        NSGradient(colors: [NSColor(srgbRed: 0.2, green: 0.165, blue: 0.13, alpha: 1), NSColor(srgbRed: 0.075, green: 0.062, blue: 0.052, alpha: 1)])!
            .draw(in: plate, angle: -90)
        NSColor.white.withAlphaComponent(0.14).setStroke()
        plate.lineWidth = 6
        plate.stroke()
        let configuration = NSImage.SymbolConfiguration(pointSize: 360, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [NSColor(srgbRed: 0.9, green: 0.81, blue: 0.64, alpha: 1)]))
        if let glyph = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(configuration) {
            let size = glyph.size
            glyph.draw(in: NSRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height))
        }
        return true
    }
}

let arguments = CommandLine.arguments
guard arguments.count == 3 else { exit(1) }
let ok = NSWorkspace.shared.setIcon(icon("arrow.down.to.line"), forFile: arguments[1], options: [])
    && NSWorkspace.shared.setIcon(icon("questionmark"), forFile: arguments[2], options: [])
exit(ok ? 0 : 1)
