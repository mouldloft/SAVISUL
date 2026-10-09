import AppKit
import Carbon.HIToolbox
import SwiftUI

enum SnapAction: String, CaseIterable, Identifiable {
    case left, right, top, bottom
    case topLeft, topRight, bottomLeft, bottomRight
    case firstThird, centerThird, lastThird, firstTwoThirds, lastTwoThirds
    case maximize, almostMaximize, center, smaller, larger
    case previousDisplay, nextDisplay, restore

    var id: String { rawValue }

    var combo: KeyCombo {
        switch self {
        case .left: return .control(kVK_LeftArrow)
        case .right: return .control(kVK_RightArrow)
        case .top: return .control(kVK_UpArrow)
        case .bottom: return .control(kVK_DownArrow)
        case .topLeft: return .control(kVK_ANSI_U)
        case .topRight: return .control(kVK_ANSI_I)
        case .bottomLeft: return .control(kVK_ANSI_J)
        case .bottomRight: return .control(kVK_ANSI_K)
        case .firstThird: return .control(kVK_ANSI_D)
        case .centerThird: return .control(kVK_ANSI_F)
        case .lastThird: return .control(kVK_ANSI_G)
        case .firstTwoThirds: return .control(kVK_ANSI_E)
        case .lastTwoThirds: return .control(kVK_ANSI_T)
        case .maximize: return .control(kVK_Return)
        case .almostMaximize: return .control(kVK_Return, shift: true)
        case .center: return .control(kVK_ANSI_C)
        case .smaller: return .control(kVK_ANSI_Minus)
        case .larger: return .control(kVK_ANSI_Equal)
        case .previousDisplay: return .control(kVK_LeftArrow, command: true)
        case .nextDisplay: return .control(kVK_RightArrow, command: true)
        case .restore: return .control(kVK_Delete)
        }
    }

    var title: Phrase {
        switch self {
        case .left: return Phrase("Left half", ru: "Левая половина", uk: "Ліва половина", fr: "Moitié gauche")
        case .right: return Phrase("Right half", ru: "Правая половина", uk: "Права половина", fr: "Moitié droite")
        case .top: return Phrase("Top half", ru: "Верхняя половина", uk: "Верхня половина", fr: "Moitié haute")
        case .bottom: return Phrase("Bottom half", ru: "Нижняя половина", uk: "Нижня половина", fr: "Moitié basse")
        case .topLeft: return Phrase("Top left", ru: "Слева сверху", uk: "Ліворуч угорі", fr: "En haut à gauche")
        case .topRight: return Phrase("Top right", ru: "Справа сверху", uk: "Праворуч угорі", fr: "En haut à droite")
        case .bottomLeft: return Phrase("Bottom left", ru: "Слева снизу", uk: "Ліворуч унизу", fr: "En bas à gauche")
        case .bottomRight: return Phrase("Bottom right", ru: "Справа снизу", uk: "Праворуч унизу", fr: "En bas à droite")
        case .firstThird: return Phrase("First third", ru: "Первая треть", uk: "Перша третина", fr: "Premier tiers")
        case .centerThird: return Phrase("Center third", ru: "Средняя треть", uk: "Середня третина", fr: "Tiers central")
        case .lastThird: return Phrase("Last third", ru: "Последняя треть", uk: "Остання третина", fr: "Dernier tiers")
        case .firstTwoThirds: return Phrase("First two thirds", ru: "Две трети слева", uk: "Дві третини ліворуч", fr: "Deux tiers gauche")
        case .lastTwoThirds: return Phrase("Last two thirds", ru: "Две трети справа", uk: "Дві третини праворуч", fr: "Deux tiers droite")
        case .maximize: return Phrase("Fill screen", ru: "Во весь экран", uk: "На весь екран", fr: "Plein écran")
        case .almostMaximize: return Phrase("Almost full", ru: "Почти весь экран", uk: "Майже весь екран", fr: "Presque plein")
        case .center: return Phrase("Center", ru: "По центру", uk: "По центру", fr: "Centrer")
        case .smaller: return Phrase("Smaller", ru: "Меньше", uk: "Менше", fr: "Plus petit")
        case .larger: return Phrase("Larger", ru: "Больше", uk: "Більше", fr: "Plus grand")
        case .previousDisplay: return Phrase("Previous display", ru: "На прошлый монитор", uk: "На попередній монітор", fr: "Écran précédent")
        case .nextDisplay: return Phrase("Next display", ru: "На следующий монитор", uk: "На наступний монітор", fr: "Écran suivant")
        case .restore: return Phrase("Restore", ru: "Вернуть как было", uk: "Повернути як було", fr: "Restaurer")
        }
    }

    /// Target rectangle inside the visible area of a screen, both in top-left coordinates.
    /// Pressing the same half again cycles ½ → ⅔ → ⅓.
    static func frame(_ action: SnapAction, visible v: CGRect, current: CGRect, cycle: Int) -> CGRect {
        let fractions: [CGFloat] = [1 / 2, 2 / 3, 1 / 3]
        let f = fractions[cycle % fractions.count]
        let portrait = v.height > v.width
        func columns(_ start: CGFloat, _ span: CGFloat) -> CGRect {
            portrait
                ? CGRect(x: v.minX, y: v.minY + v.height * start, width: v.width, height: v.height * span)
                : CGRect(x: v.minX + v.width * start, y: v.minY, width: v.width * span, height: v.height)
        }
        switch action {
        case .left: return CGRect(x: v.minX, y: v.minY, width: v.width * f, height: v.height)
        case .right: return CGRect(x: v.maxX - v.width * f, y: v.minY, width: v.width * f, height: v.height)
        case .top: return CGRect(x: v.minX, y: v.minY, width: v.width, height: v.height * f)
        case .bottom: return CGRect(x: v.minX, y: v.maxY - v.height * f, width: v.width, height: v.height * f)
        case .topLeft: return CGRect(x: v.minX, y: v.minY, width: v.width / 2, height: v.height / 2)
        case .topRight: return CGRect(x: v.midX, y: v.minY, width: v.width / 2, height: v.height / 2)
        case .bottomLeft: return CGRect(x: v.minX, y: v.midY, width: v.width / 2, height: v.height / 2)
        case .bottomRight: return CGRect(x: v.midX, y: v.midY, width: v.width / 2, height: v.height / 2)
        case .firstThird: return columns(0, 1 / 3)
        case .centerThird: return columns(1 / 3, 1 / 3)
        case .lastThird: return columns(2 / 3, 1 / 3)
        case .firstTwoThirds: return columns(0, 2 / 3)
        case .lastTwoThirds: return columns(1 / 3, 2 / 3)
        case .maximize: return v
        case .almostMaximize: return v.insetBy(dx: v.width * 0.05, dy: v.height * 0.05)
        case .center:
            let width = min(current.width, v.width)
            let height = min(current.height, v.height)
            return CGRect(x: v.midX - width / 2, y: v.midY - height / 2, width: width, height: height)
        case .smaller, .larger:
            let delta: CGFloat = action == .smaller ? -40 : 40
            let width = min(max(current.width + delta * 2, 320), v.width)
            let height = min(max(current.height + delta * 2, 220), v.height)
            var frame = CGRect(x: current.midX - width / 2, y: current.midY - height / 2, width: width, height: height)
            frame.origin.x = min(max(frame.minX, v.minX), v.maxX - width)
            frame.origin.y = min(max(frame.minY, v.minY), v.maxY - height)
            return frame
        case .previousDisplay, .nextDisplay, .restore:
            return current
        }
    }
}

/// Keyboard window layout plus the restore memory and the on-screen footprint.
@MainActor
final class Snapper {
    private struct Last {
        var action: SnapAction
        var window: CGWindowID?
        var frame: CGRect
        var cycle: Int
        var at: Date
    }

    private var last: Last?
    private var restore: [CGWindowID: CGRect] = [:]
    private var registered = false
    let preview = SnapPreview()

    func enable(_ on: Bool) {
        guard on != registered else { return }
        registered = on
        for action in SnapAction.allCases {
            let name = "snap.\(action.rawValue)"
            if on {
                HotKeyCenter.shared.register(name, action.combo) { Suite.shared.windows.snapper.perform(action) }
            } else {
                HotKeyCenter.shared.unregister(name)
            }
        }
    }

    /// The window the user is looking at: SAVISUL's own panels never count.
    static func frontWindow() -> (AXUIElement, pid_t)? {
        let me = ProcessInfo.processInfo.processIdentifier
        var app = NSWorkspace.shared.frontmostApplication
        if app?.processIdentifier == me { app = WindowCatalog.shared.previousApp }
        guard let pid = app?.processIdentifier else { return nil }
        if let focused = AX.focusedWindow(pid), AX.isStandardWindow(focused) { return (focused, pid) }
        if let first = AX.windows(pid).first(where: { AX.isStandardWindow($0) && AX.bool($0, kAXMinimizedAttribute) != true }) {
            return (first, pid)
        }
        return nil
    }

    func perform(_ action: SnapAction) {
        guard AX.trusted else {
            Suite.shared.askAccessibility()
            return
        }
        guard let (window, _) = Self.frontWindow(), let current = AX.frame(window) else {
            NSSound.beep()
            return
        }
        apply(action, to: window, current: current)
    }

    func apply(_ action: SnapAction, to window: AXUIElement, current: CGRect) {
        let id = AX.windowID(window)
        let screen = ScreenSpace.screen(forAX: current)
        let visible = ScreenSpace.toAX(screen.visibleFrame)
        switch action {
        case .restore:
            guard let id, let saved = restore[id] else {
                NSSound.beep()
                return
            }
            AX.setFrame(window, saved)
            restore[id] = nil
            last = nil
            preview.flash(AX.frame(window) ?? saved)
        case .previousDisplay, .nextDisplay:
            let screens = NSScreen.screens.sorted { $0.frame.minX < $1.frame.minX }
            guard screens.count > 1, let index = screens.firstIndex(of: screen) else {
                NSSound.beep()
                return
            }
            let target = screens[(index + (action == .nextDisplay ? 1 : -1) + screens.count) % screens.count]
            let destination = ScreenSpace.toAX(target.visibleFrame)
            remember(id, current)
            let frame = Self.carry(current, from: visible, to: destination)
            AX.setFrame(window, frame)
            last = nil
            preview.flash(AX.frame(window) ?? frame)
        default:
            var cycle = 0
            if let last, last.action == action, last.window == id, Self.close(last.frame, current), Date().timeIntervalSince(last.at) < 6 {
                cycle = last.cycle + 1
            }
            if !(last.map { Self.close($0.frame, current) && $0.window == id } ?? false) { remember(id, current) }
            let target = SnapAction.frame(action, visible: visible, current: current, cycle: cycle).integral
            AX.setFrame(window, target)
            let actual = AX.frame(window) ?? target
            last = Last(action: action, window: id, frame: actual, cycle: cycle, at: Date())
            preview.flash(actual)
        }
    }

    private func remember(_ id: CGWindowID?, _ frame: CGRect) {
        guard let id else { return }
        restore[id] = frame
        if restore.count > 200 { restore.removeAll() }
    }

    static func close(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) < 6 && abs(a.minY - b.minY) < 6 && abs(a.width - b.width) < 6 && abs(a.height - b.height) < 6
    }

    /// Same place relative to the screen; a window that filled one screen fills the other.
    static func carry(_ frame: CGRect, from: CGRect, to: CGRect) -> CGRect {
        if close(frame, from) { return to }
        let width = min(frame.width, to.width)
        let height = min(frame.height, to.height)
        let rx = from.width > frame.width ? (frame.minX - from.minX) / (from.width - frame.width) : 0.5
        let ry = from.height > frame.height ? (frame.minY - from.minY) / (from.height - frame.height) : 0.5
        let x = to.minX + (to.width - width) * min(max(rx, 0), 1)
        let y = to.minY + (to.height - height) * min(max(ry, 0), 1)
        return CGRect(x: x, y: y, width: width, height: height).integral
    }
}

/// Glass outline of where a window lands: flashed after a shortcut, held while dragging to an edge.
@MainActor
final class SnapPreview {
    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?
    private(set) var showing: CGRect?

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.floatingWindow)) + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.animationBehavior = .none
        panel.contentView = NSHostingView(rootView: SnapFootprint())
        self.panel = panel
        return panel
    }

    /// Holds the outline at a frame given in top-left coordinates.
    func hold(_ frame: CGRect) {
        hideWork?.cancel()
        let panel = panel ?? makePanel()
        let target = ScreenSpace.toAppKit(frame).insetBy(dx: 4, dy: 4)
        if showing == nil || !panel.isVisible {
            panel.setFrame(target.insetBy(dx: target.width * 0.04, dy: target.height * 0.04), display: false)
            panel.alphaValue = 0
            panel.orderFrontRegardless()
        }
        showing = frame
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(target, display: true)
        }
    }

    func release() {
        guard let panel, showing != nil else { return }
        showing = nil
        Glass.fadeOut(panel, duration: 0.16)
    }

    func flash(_ frame: CGRect) {
        guard Suite.shared.settings.snapping else { return }
        hold(frame)
        let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.release() } }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28, execute: work)
    }
}

private struct SnapFootprint: View {
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        ZStack {
            shape.fill(.ultraThinMaterial).opacity(0.55)
            shape.fill(Palette.accent.opacity(0.12))
            shape.strokeBorder(LinearGradient(colors: [Palette.accent.opacity(0.95), Palette.accent.opacity(0.45)],
                                              startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 2.5)
        }
        .environment(\.colorScheme, .dark)
    }
}

/// A miniature screen with the target area lit, for the settings list.
struct LayoutGlyph: View {
    let action: SnapAction
    var size = CGSize(width: 30, height: 20)

    var body: some View {
        let unit = CGRect(origin: .zero, size: size)
        let current = CGRect(x: size.width * 0.2, y: size.height * 0.2, width: size.width * 0.6, height: size.height * 0.6)
        let area: CGRect = {
            switch action {
            case .previousDisplay: return CGRect(x: 0, y: 0, width: size.width * 0.42, height: size.height)
            case .nextDisplay: return CGRect(x: size.width * 0.58, y: 0, width: size.width * 0.42, height: size.height)
            case .restore: return current
            default: return SnapAction.frame(action, visible: unit, current: current, cycle: 0)
            }
        }()
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(Palette.secondary, lineWidth: 1)
            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                .fill(Palette.accent)
                .frame(width: max(area.width - 3, 2), height: max(area.height - 3, 2))
                .offset(x: area.minX + 1.5, y: area.minY + 1.5)
            if action == .previousDisplay || action == .nextDisplay {
                Image(systemName: action == .nextDisplay ? "arrow.right" : "arrow.left")
                    .font(.system(size: 8, weight: .bold)).foregroundStyle(Palette.ink)
                    .frame(width: size.width, height: size.height)
            } else if action == .restore {
                Image(systemName: "arrow.uturn.backward").font(.system(size: 8, weight: .bold)).foregroundStyle(Palette.onLight)
                    .frame(width: size.width, height: size.height)
            }
        }
        .frame(width: size.width, height: size.height)
    }
}
