import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Shake the pointer while dragging and a shelf opens right there; drop now, drag out later.
@MainActor
final class ShelfPanel {
    private var panel: OverlayPanel?
    private var monitors: [Any] = []
    private var dragChange = 0
    private var direction: CGFloat = 0
    private var extreme: CGFloat = 0
    private var reversals: [Date] = []
    private var cooldown = Date.distantPast
    private var hideWork: DispatchWorkItem?
    private let state = ShelfPanelState()
    private static let size = NSSize(width: 360, height: 196)

    func enable(shake: Bool) {
        if shake, monitors.isEmpty {
            if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp], handler: { event in
                let type = event.type
                let location = NSEvent.mouseLocation
                MainActor.assumeIsolated { Suite.shared.clipboard.shelfPanel.track(type, location) }
            }) { monitors.append(monitor) }
        } else if !shake {
            monitors.forEach { NSEvent.removeMonitor($0) }
            monitors = []
        }
    }

    private func track(_ type: NSEvent.EventType, _ location: NSPoint) {
        switch type {
        case .leftMouseDown:
            dragChange = NSPasteboard(name: .drag).changeCount
            reversals = []
            direction = 0
            extreme = location.x
        case .leftMouseDragged:
            guard NSPasteboard(name: .drag).changeCount != dragChange, Date() > cooldown else { return }
            let x = location.x
            if direction == 0 {
                if abs(x - extreme) > 18 {
                    direction = x > extreme ? 1 : -1
                    extreme = x
                }
                return
            }
            if (x - extreme) * direction > 0 {
                extreme = x
            } else if abs(x - extreme) > 26 {
                direction = -direction
                extreme = x
                reversals.append(Date())
            }
            reversals.removeAll { Date().timeIntervalSince($0) > 0.7 }
            if reversals.count >= 4 {
                reversals = []
                cooldown = Date().addingTimeInterval(1.5)
                show(near: location)
            }
        case .leftMouseUp:
            reversals = []
            direction = 0
            if panel?.isVisible == true, Suite.shared.shelf.items.isEmpty { scheduleHide(4) }
        default:
            break
        }
    }

    func toggle() {
        if panel?.isVisible == true { hide() } else { show(near: nil) }
    }

    func show(near point: NSPoint?) {
        hideWork?.cancel()
        let panel = self.panel ?? make()
        let screen = point.flatMap { p in NSScreen.screens.first { NSMouseInRect(p, $0.frame, false) } } ?? ScreenSpace.mouseScreen
        let visible = screen.visibleFrame
        var origin: NSPoint
        if let point {
            origin = NSPoint(x: point.x + 28, y: point.y - Self.size.height / 2)
            if origin.x + Self.size.width > visible.maxX - 8 { origin.x = point.x - Self.size.width - 28 }
        } else {
            origin = NSPoint(x: visible.midX - Self.size.width / 2, y: visible.minY + 90)
        }
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - Self.size.width - 8)
        origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - Self.size.height - 8)
        let frame = NSRect(origin: origin, size: Self.size)
        if panel.isVisible {
            panel.setFrame(frame, display: true)
        } else {
            Glass.fadeIn(panel, to: frame, lift: 0, key: false)
            if Suite.shared.settings.islandHaptics { NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now) }
        }
    }

    func hide() {
        hideWork?.cancel()
        if let panel { Glass.fadeOut(panel) }
    }

    private func scheduleHide(_ delay: TimeInterval) {
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, Suite.shared.shelf.items.isEmpty, !self.state.targeted else { return }
                self.hide()
            }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func make() -> OverlayPanel {
        let panel = OverlayPanel(size: Self.size, key: false, level: NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.floatingWindow)) + 2))
        panel.contentView = Glass.host(ShelfPanelView(shelf: Suite.shared.shelf, state: state, close: { [weak self] in self?.hide() }),
                                       size: Self.size, radius: 22)
        self.panel = panel
        return panel
    }
}

@MainActor
@Observable
final class ShelfPanelState {
    var targeted = false
}

private struct ShelfPanelView: View {
    let shelf: ShelfStore
    let state: ShelfPanelState
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "tray.full.fill").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.accent)
                Text(ShelfPhrases.title.text).font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.ink)
                if !shelf.items.isEmpty {
                    Text("\(shelf.items.count)").font(.system(size: 11, weight: .semibold).monospacedDigit()).foregroundStyle(Palette.tertiary)
                }
                Spacer(minLength: 0)
                if !shelf.files.isEmpty {
                    RoundIcon(symbol: "airplayaudio", help: "AirDrop") { shelf.airDrop() }
                    RoundIcon(symbol: "folder", help: Phrases.reveal.text) { shelf.reveal() }
                }
                if !shelf.items.isEmpty {
                    RoundIcon(symbol: "trash", help: Phrases.clear.text) { shelf.clear() }
                }
                RoundIcon(symbol: "xmark", help: Phrases.done.text, action: close)
            }
            if shelf.items.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: state.targeted ? "tray.and.arrow.down.fill" : "tray.and.arrow.down")
                        .font(.system(size: 26, weight: .light))
                        .foregroundStyle(state.targeted ? Palette.accent : Palette.secondary)
                        .symbolEffect(.bounce, value: state.targeted)
                    Text(ShelfPhrases.drop.text).font(.system(size: 12)).foregroundStyle(Palette.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(state.targeted ? Palette.accent : Color.white.opacity(0.18), style: StrokeStyle(lineWidth: 1.4, dash: [6, 5])))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(shelf.items) { item in ShelfTile(item: item, shelf: shelf) }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(state.targeted ? Palette.accent.opacity(0.12) : Color.clear))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDrop(of: [.fileURL, .url, .image, .plainText], isTargeted: Binding(get: { state.targeted }, set: { state.targeted = $0 })) { providers in
            shelf.accept(providers)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.82), value: shelf.items.count)
        .animation(.easeOut(duration: 0.15), value: state.targeted)
    }
}

enum ShelfPhrases {
    static let title = Phrase("Shelf", ru: "Полка", uk: "Полиця", fr: "Étagère")
    static let drop = Phrase("Drop files, links or text here", ru: "Бросьте сюда файлы, ссылки или текст",
                             uk: "Киньте сюди файли, посилання або текст", fr: "Déposez fichiers, liens ou texte ici")
}
