import AppKit
import SwiftUI

/// An image pinned above every window: drag it anywhere, scroll to resize, hover for Copy and Close.
@MainActor
final class PinWindow: NSPanel {
    private static var open: [PinWindow] = []
    private let image: NSImage
    private var aspect: CGFloat

    static func pin(_ image: NSImage, title: String?) {
        let window = PinWindow(image: image)
        open.append(window)
        let screen = ScreenSpace.mouseScreen.visibleFrame
        let side: CGFloat = 320
        let size = image.size.width >= image.size.height
            ? NSSize(width: min(side, image.size.width), height: min(side, image.size.width) / max(window.aspect, 0.01))
            : NSSize(width: min(side, image.size.height) * window.aspect, height: min(side, image.size.height))
        let mouse = NSEvent.mouseLocation
        var origin = NSPoint(x: mouse.x - size.width / 2, y: mouse.y - size.height / 2)
        origin.x = min(max(origin.x, screen.minX + 12), screen.maxX - size.width - 12)
        origin.y = min(max(origin.y, screen.minY + 12), screen.maxY - size.height - 12)
        window.setFrame(NSRect(origin: origin, size: size), display: false)
        window.alphaValue = 0
        window.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            window.animator().alphaValue = 1
        }
        window.title = title ?? ""
    }

    private init(image: NSImage) {
        self.image = image
        aspect = image.size.height > 0 ? image.size.width / image.size.height : 1
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel, .resizable], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        contentAspectRatio = image.size
        contentView = NSHostingView(rootView: PinView(image: image, copy: { [weak self] in self?.copyImage() }, close: { [weak self] in self?.dismiss() }))
    }

    override var canBecomeKey: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 || (event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "w") {
            dismiss()
        } else if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "c" {
            copyImage()
        } else {
            super.keyDown(with: event)
        }
    }

    /// Scrolling grows or shrinks the pin around its centre.
    override func scrollWheel(with event: NSEvent) {
        let factor = 1 + event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 0.004 : 0.04)
        var frame = self.frame
        let width = min(max(frame.width * factor, 80), 2400)
        let height = width / max(aspect, 0.01)
        frame.origin.x += (frame.width - width) / 2
        frame.origin.y += (frame.height - height) / 2
        frame.size = NSSize(width: width, height: height)
        setFrame(frame, display: true)
    }

    private func copyImage() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
        Suite.shared.notify(IslandNotice(symbol: "doc.on.doc.fill", tint: Palette.accent, title: Phrases.copy.text, detail: nil, duration: 1.4))
    }

    private func dismiss() {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.14
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.orderOut(nil)
                Self.open.removeAll { $0 === self }
            }
        })
    }
}

private struct PinView: View {
    let image: NSImage
    let copy: () -> Void
    let close: () -> Void
    @State private var hover = false

    var body: some View {
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fill)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.white.opacity(hover ? 0.5 : 0.18), lineWidth: 1))
            .overlay(alignment: .topTrailing) {
                if hover {
                    HStack(spacing: 6) {
                        button("doc.on.doc", Phrases.copy.text, copy)
                        button("xmark", Phrases.close.text, close)
                    }
                    .padding(8)
                    .transition(.opacity)
                }
            }
            .onHover { inside in withAnimation(.easeOut(duration: 0.15)) { hover = inside } }
            .onTapGesture(count: 2, perform: close)
            .contextMenu {
                Button(Phrases.copy.text, action: copy)
                Button(Phrases.close.text, action: close)
            }
    }

    private func button(_ symbol: String, _ help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 10.5, weight: .bold)).foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.black.opacity(0.62)))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
