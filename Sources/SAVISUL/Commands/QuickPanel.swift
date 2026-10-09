import AppKit
import SwiftUI

/// ⌃⌥P: a small floating palette of favourite actions that stays where you leave it.
@MainActor
final class QuickPanel {
    private var panel: OverlayPanel?
    private var dragOrigin: NSPoint?
    private static let originKey = "suite.quickOrigin"

    var isVisible: Bool { panel?.isVisible == true }

    func toggle() { isVisible ? hide() : show() }

    func show() {
        let panel = self.panel ?? make()
        let size = Self.size(for: Suite.shared.settings.favorites.count)
        let screen = ScreenSpace.mouseScreen.visibleFrame
        var origin = NSPoint(x: screen.maxX - size.width - 24, y: screen.midY - size.height / 2)
        if let saved = UserDefaults.standard.string(forKey: Self.originKey) {
            let point = NSPointFromString(saved)
            if NSScreen.screens.contains(where: { NSPointInRect(NSPoint(x: point.x + 20, y: point.y + 20), $0.visibleFrame) }) { origin = point }
        }
        Glass.fadeIn(panel, to: NSRect(origin: origin, size: size), lift: 6, key: false)
    }

    func hide() {
        guard let panel else { return }
        UserDefaults.standard.set(NSStringFromPoint(panel.frame.origin), forKey: Self.originKey)
        Glass.fadeOut(panel)
    }

    /// Re-lays the palette after favourites change.
    func refresh() {
        guard let panel, panel.isVisible else { return }
        let size = Self.size(for: Suite.shared.settings.favorites.count)
        var frame = panel.frame
        frame.origin.y += frame.height - size.height
        frame.size = size
        panel.setFrame(frame, display: true, animate: true)
    }

    private static func size(for count: Int) -> NSSize {
        let columns = 4
        let rows = max(1, Int(ceil(Double(max(count, 1)) / Double(columns))))
        return NSSize(width: CGFloat(columns) * 80 + 24, height: CGFloat(rows) * 84 + 58)
    }

    fileprivate func drag(_ translation: CGSize, ended: Bool) {
        guard let panel else { return }
        if dragOrigin == nil { dragOrigin = panel.frame.origin }
        guard let start = dragOrigin else { return }
        panel.setFrameOrigin(NSPoint(x: start.x + translation.width, y: start.y - translation.height))
        if ended {
            dragOrigin = nil
            UserDefaults.standard.set(NSStringFromPoint(panel.frame.origin), forKey: Self.originKey)
        }
    }

    private func make() -> OverlayPanel {
        let size = Self.size(for: Suite.shared.settings.favorites.count)
        let panel = OverlayPanel(size: size, key: false, level: .floating)
        panel.contentView = Glass.host(QuickPanelView(settings: Suite.shared.settings,
                                                      drag: { translation, ended in Suite.shared.commands.quick.drag(translation, ended: ended) },
                                                      close: { Suite.shared.commands.quick.hide() }),
                                       size: size, radius: 22)
        self.panel = panel
        return panel
    }
}

private struct QuickPanelView: View {
    let settings: SuiteSettings
    let drag: (CGSize, Bool) -> Void
    let close: () -> Void

    var body: some View {
        let actions = settings.favorites.compactMap(SuiteActions.action)
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal").font(.system(size: 10, weight: .bold)).foregroundStyle(Palette.tertiary)
                Text(QuickPhrases.title.text).font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.secondary)
                Spacer(minLength: 0)
                Button { Suite.shared.openSettings() } label: {
                    Text(QuickPhrases.edit.text).font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.accent)
                }
                .buttonStyle(.plain)
                Button(action: close) {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Palette.secondary)
                        .frame(width: 20, height: 20).background(Circle().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(PressableStyle())
            }
            .frame(height: 22)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { drag($0.translation, false) }
                .onEnded { drag($0.translation, true) })
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(76), spacing: 4), count: 4), spacing: 4) {
                ForEach(actions) { action in QuickTile(action: action) }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct QuickTile: View {
    let action: SuiteAction
    @State private var hover = false

    var body: some View {
        Button { action.run() } label: {
            VStack(spacing: 6) {
                Image(systemName: action.symbol).font(.system(size: 17, weight: .semibold)).foregroundStyle(action.tint)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(action.tint.opacity(hover ? 0.24 : 0.14)))
                Text(SuiteActions.title(action)).font(.system(size: 10, weight: .medium)).foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.center).lineLimit(2).frame(height: 26, alignment: .top)
            }
            .frame(width: 76, height: 80)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(hover ? 0.08 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .onHover { hover = $0 }
        .help(SuiteActions.title(action))
    }
}

enum QuickPhrases {
    static let title = Phrase("Favorites", ru: "Избранное", uk: "Вибране", fr: "Favoris")
    static let edit = Phrase("Edit", ru: "Изменить", uk: "Змінити", fr: "Modifier")
}
