import AppKit
import SwiftUI

/// A borderless panel that floats over every Space. Key panels take typing without activating SAVISUL,
/// so the app underneath stays in front and receives the paste or the command afterwards.
final class OverlayPanel: NSPanel {
    var acceptsKey: Bool
    var onResignKey: (() -> Void)?

    init(size: NSSize, key: Bool, level: NSWindow.Level = .floating) {
        acceptsKey = key
        super.init(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        self.level = level
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        isMovableByWindowBackground = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        appearance = NSAppearance(named: .darkAqua)
    }

    override var canBecomeKey: Bool { acceptsKey }
    override var canBecomeMain: Bool { false }

    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }
}

/// Floating panels never become key, so the first click has to reach SwiftUI directly.
final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
enum Glass {
    /// SwiftUI content on the same dark glass as the SAVISUL panel.
    static func host<Content: View>(_ content: Content, size: NSSize, radius: CGFloat, material: NSVisualEffectView.Material = .hudWindow) -> NSView {
        let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        effect.material = material
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.maskImage = Mark.roundedMask(radius: radius)
        effect.autoresizingMask = [.width, .height]
        let hosting = FirstClickHostingView(rootView: content.environment(\.colorScheme, .dark))
        hosting.frame = effect.bounds
        hosting.autoresizingMask = [.width, .height]
        effect.addSubview(hosting)
        return effect
    }

    /// Transparent SwiftUI content for panels that draw their own shapes.
    static func clear<Content: View>(_ content: Content, size: NSSize) -> NSView {
        let hosting = FirstClickHostingView(rootView: content.environment(\.colorScheme, .dark))
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.autoresizingMask = [.width, .height]
        return hosting
    }

    static func fadeIn(_ panel: NSPanel, to frame: NSRect, lift: CGFloat = 10, key: Bool) {
        panel.setFrame(frame.offsetBy(dx: 0, dy: -lift), display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        if key { panel.makeKey() }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(frame, display: true)
        }
    }

    static func fadeOut(_ panel: NSPanel, duration: Double = 0.14, completion: (() -> Void)? = nil) {
        guard panel.isVisible else {
            completion?()
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated {
                if panel.alphaValue < 0.01 { panel.orderOut(nil) }
                panel.alphaValue = 1
                completion?()
            }
        })
    }

    /// Centered horizontally, a little above the middle, like Spotlight.
    static func spotlightFrame(size: NSSize, on screen: NSScreen? = nil) -> NSRect {
        let visible = (screen ?? ScreenSpace.mouseScreen).visibleFrame
        let x = visible.midX - size.width / 2
        let y = visible.minY + visible.height * 0.62 - size.height / 2
        return NSRect(x: x, y: min(y, visible.maxY - size.height - 40), width: size.width, height: size.height)
    }
}

/// Keyboard shortcut chips used across settings and panels.
struct KeyCaps: View {
    let keys: [String]
    var size: CGFloat = 22

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                Text(key)
                    .font(.system(size: size * 0.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(Palette.ink)
                    .padding(.horizontal, key.count > 1 ? 6 : 0)
                    .frame(minWidth: size, minHeight: size)
                    .background(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous).fill(Color.white.opacity(0.08)))
                    .overlay(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous).strokeBorder(Color.white.opacity(0.14), lineWidth: 0.6))
            }
        }
    }
}
