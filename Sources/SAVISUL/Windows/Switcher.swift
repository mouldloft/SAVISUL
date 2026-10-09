import AppKit
import Carbon.HIToolbox
import Observation
import SwiftUI

@MainActor
@Observable
final class SwitcherModel {
    var entries: [WindowEntry] = []
    var selection = 0
    var thumbnails: [CGWindowID: NSImage] = [:]
    var previews = true
    var onlyApp: String?
    var tile = CGSize(width: 220, height: 168)
    var columns = 5
    var loading = true
}

/// ⌥Tab through every window with live pictures, ⌥` through the front app's windows,
/// and optionally ⌘Tab in place of the system switcher. Releasing the modifier switches.
@MainActor
final class Switcher {
    private let model = SwitcherModel()
    private var panel: OverlayPanel?
    private(set) var open = false
    private var visible = false
    private var trigger: CGEventFlags = .maskAlternate
    private var showWork: DispatchWorkItem?
    private var loadTask: Task<Void, Never>?
    private var pendingSteps = 0
    private var loaded = false
    private var commandTab = false
    private var mouseAtShow = NSPoint.zero

    func enable(commandTab: Bool) {
        if !InputTap.shared.has("switcher") {
            InputTap.shared.add("switcher", priority: 50, types: [.keyDown, .keyUp, .flagsChanged]) { [weak self] type, event in
                guard let self else { return event }
                return self.handle(type, event)
            }
        }
        setCommandTab(commandTab)
    }

    func disable() {
        InputTap.shared.remove("switcher")
        setCommandTab(false)
        cancel()
    }

    private func setCommandTab(_ on: Bool) {
        guard on != commandTab else { return }
        commandTab = on
        SymbolicHotKeys.set([1, 2], enabled: !on)
    }

    // MARK: Keys

    private func handle(_ type: CGEventType, _ event: CGEvent) -> CGEvent? {
        let flags = event.flags
        let code = Int(event.getIntegerValueField(.keyboardEventKeycode))
        switch type {
        case .keyDown:
            if open { return keyWhileOpen(code, flags: flags) }
            let option = flags.contains(.maskAlternate)
            let command = flags.contains(.maskCommand)
            let control = flags.contains(.maskControl)
            let back = flags.contains(.maskShift)
            if code == kVK_Tab && option && !command && !control {
                begin(trigger: .maskAlternate, onlyFront: false, backwards: back)
                return nil
            }
            if code == kVK_ANSI_Grave && option && !command && !control {
                begin(trigger: .maskAlternate, onlyFront: true, backwards: back)
                return nil
            }
            if commandTab && code == kVK_Tab && command && !option && !control {
                begin(trigger: .maskCommand, onlyFront: false, backwards: back)
                return nil
            }
            return event
        case .keyUp:
            return open ? nil : event
        case .flagsChanged:
            if open && !flags.contains(trigger) { commit() }
            return event
        default:
            return event
        }
    }

    private func keyWhileOpen(_ code: Int, flags: CGEventFlags) -> CGEvent? {
        switch code {
        case kVK_Tab, kVK_ANSI_Grave: step(flags.contains(.maskShift) ? -1 : 1)
        case kVK_RightArrow: step(1)
        case kVK_LeftArrow: step(-1)
        case kVK_DownArrow: step(model.columns)
        case kVK_UpArrow: step(-model.columns)
        case kVK_Escape: cancel()
        case kVK_Return, kVK_Space: commit()
        case kVK_ANSI_Q: act(.quit)
        case kVK_ANSI_W: act(.close)
        case kVK_ANSI_M: act(.minimize)
        case kVK_ANSI_H: act(.hide)
        default: break
        }
        return nil
    }

    // MARK: Session

    private func begin(trigger: CGEventFlags, onlyFront: Bool, backwards: Bool) {
        open = true
        self.trigger = trigger
        loaded = false
        pendingSteps = backwards ? -1 : 1
        model.entries = []
        model.selection = 0
        model.thumbnails = [:]
        model.loading = true
        let front = NSWorkspace.shared.frontmostApplication
        model.onlyApp = onlyFront ? front?.localizedName : nil
        let previews = Suite.shared.settings.switcherPreviews && WindowCatalog.shared.canCapture
        model.previews = previews
        let only = onlyFront ? front?.processIdentifier : nil
        loadTask?.cancel()
        loadTask = Task { @MainActor [weak self] in
            let entries = await WindowCatalog.shared.entries(only: only, includeEmptyApps: !onlyFront)
            guard let self, self.open else { return }
            self.model.entries = entries
            self.model.loading = false
            self.loaded = true
            self.select(self.pendingSteps)
            self.layout()
            if self.visible { self.present(animated: false) }
            if previews { await self.loadThumbnails() }
        }
        let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.show() } }
        showWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.11, execute: work)
    }

    private func loadThumbnails() async {
        let ids = model.entries.compactMap { $0.minimized || $0.hidden ? nil : $0.windowID }
        for id in ids { if let image = WindowCatalog.shared.cached(id) { model.thumbnails[id] = image } }
        let box = CGSize(width: model.tile.width - 16, height: model.tile.height - 46)
        let fresh = await WindowCatalog.shared.thumbnails(for: ids, fitting: box, maxAge: 0.6)
        guard open else { return }
        withAnimation(.easeOut(duration: 0.18)) {
            for (id, image) in fresh { model.thumbnails[id] = image }
        }
    }

    private func select(_ steps: Int) {
        let count = model.entries.count
        guard count > 0 else { return }
        if count == 1 { model.selection = 0; return }
        model.selection = ((steps % count) + count) % count
    }

    private func step(_ delta: Int) {
        guard loaded else {
            pendingSteps += delta
            return
        }
        let count = model.entries.count
        guard count > 0 else { return }
        model.selection = ((model.selection + delta) % count + count) % count
    }

    private func commit() {
        guard open else { return }
        let entry = loaded && model.entries.indices.contains(model.selection) ? model.entries[model.selection] : nil
        let fallback = loaded ? nil : WindowCatalog.shared.previousApp
        close()
        if let entry { Self.activate(entry) } else { fallback?.activate(options: []) }
    }

    private func cancel() {
        guard open else { return }
        close()
    }

    private func close() {
        open = false
        loadTask?.cancel()
        showWork?.cancel()
        showWork = nil
        if visible, let panel { Glass.fadeOut(panel, duration: 0.1) }
        visible = false
    }

    static func activate(_ entry: WindowEntry) {
        guard let app = NSRunningApplication(processIdentifier: entry.pid) else { return }
        if entry.hidden { app.unhide() }
        if let element = entry.element {
            AX.focus(element, pid: entry.pid)
        } else if let url = app.bundleURL {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        } else {
            app.activate(options: [])
        }
    }

    private enum Action { case quit, close, minimize, hide }

    private func act(_ action: Action) {
        guard loaded, model.entries.indices.contains(model.selection) else { return }
        let entry = model.entries[model.selection]
        let app = NSRunningApplication(processIdentifier: entry.pid)
        switch action {
        case .quit:
            app?.terminate()
            model.entries.removeAll { $0.pid == entry.pid }
        case .close:
            if let element = entry.element {
                AX.close(element)
                model.entries.remove(at: model.selection)
            } else {
                app?.terminate()
                model.entries.removeAll { $0.pid == entry.pid }
            }
        case .minimize:
            guard let element = entry.element else { return }
            AX.minimize(element)
            model.entries[model.selection].minimized = true
        case .hide:
            app?.hide()
            for index in model.entries.indices where model.entries[index].pid == entry.pid { model.entries[index].hidden = true }
        }
        if model.entries.isEmpty {
            cancel()
            return
        }
        model.selection = min(model.selection, model.entries.count - 1)
        layout()
        present(animated: false)
    }

    // MARK: Panel

    private func layout() {
        let screen = ScreenSpace.mouseScreen.visibleFrame
        let count = max(model.entries.count, 1)
        var tile = model.previews ? CGSize(width: 228, height: 176) : CGSize(width: 136, height: 140)
        if count > 12 { tile = CGSize(width: tile.width * 0.82, height: tile.height * 0.82) }
        if count > 24 { tile = CGSize(width: tile.width * 0.8, height: tile.height * 0.8) }
        let spacing: CGFloat = 10
        let maxWidth = screen.width * 0.9 - 36
        var columns = max(1, min(count, Int((maxWidth + spacing) / (tile.width + spacing))))
        if count <= 7 { columns = count }
        var rows = Int(ceil(Double(count) / Double(columns)))
        let maxHeight = screen.height * 0.82 - 90
        while CGFloat(rows) * (tile.height + spacing) > maxHeight && tile.width > 90 {
            tile = CGSize(width: tile.width * 0.88, height: tile.height * 0.88)
            columns = max(1, min(count, Int((maxWidth + spacing) / (tile.width + spacing))))
            rows = Int(ceil(Double(count) / Double(columns)))
        }
        model.tile = CGSize(width: tile.width.rounded(), height: tile.height.rounded())
        model.columns = columns
    }

    private var panelSize: NSSize {
        let count = max(model.entries.count, 1)
        let columns = max(model.columns, 1)
        let rows = Int(ceil(Double(count) / Double(columns)))
        let width = CGFloat(min(count, columns)) * (model.tile.width + 10) - 10 + 36
        let header: CGFloat = model.onlyApp == nil ? 0 : 30
        let height = CGFloat(rows) * (model.tile.height + 10) - 10 + 36 + header + 26
        return NSSize(width: max(width, 300), height: max(height, 120))
    }

    private func show() {
        guard open, !visible else { return }
        visible = true
        mouseAtShow = NSEvent.mouseLocation
        if loaded { layout() }
        present(animated: true)
    }

    private func present(animated: Bool) {
        guard visible else { return }
        let size = loaded ? panelSize : NSSize(width: 300, height: 120)
        let panel = self.panel ?? makePanel()
        let screen = ScreenSpace.mouseScreen.visibleFrame
        let frame = NSRect(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2 + screen.height * 0.04,
                           width: size.width, height: size.height)
        if animated {
            Glass.fadeIn(panel, to: frame, lift: 0, key: false)
        } else {
            panel.setFrame(frame, display: true)
            panel.orderFrontRegardless()
        }
    }

    private func makePanel() -> OverlayPanel {
        let panel = OverlayPanel(size: NSSize(width: 300, height: 120), key: false,
                                 level: NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.popUpMenuWindow)) + 2))
        let view = SwitcherView(model: model, pick: { [weak self] index in
            guard let self else { return }
            self.model.selection = index
            self.commit()
        }, hover: { [weak self] index in
            guard let self else { return }
            let mouse = NSEvent.mouseLocation
            if hypot(mouse.x - self.mouseAtShow.x, mouse.y - self.mouseAtShow.y) > 3 { self.model.selection = index }
        })
        panel.contentView = Glass.host(view, size: panel.frame.size, radius: 26)
        self.panel = panel
        return panel
    }
}

/// Turns the system ⌘Tab on and off while SAVISUL replaces it. WindowServer resets it at logout.
enum SymbolicHotKeys {
    private typealias SetEnabled = @convention(c) (Int32, Bool) -> Int32
    private static let function: SetEnabled? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
              let symbol = dlsym(handle, "CGSSetSymbolicHotKeyEnabled") else { return nil }
        return unsafeBitCast(symbol, to: SetEnabled.self)
    }()

    static func set(_ keys: [Int32], enabled: Bool) {
        guard let function else { return }
        for key in keys { _ = function(key, enabled) }
    }
}

private struct SwitcherView: View {
    let model: SwitcherModel
    let pick: (Int) -> Void
    let hover: (Int) -> Void

    var body: some View {
        VStack(spacing: 10) {
            if let app = model.onlyApp {
                Text(app).font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.secondary)
            }
            if model.loading {
                Spinner(size: 18).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(model.tile.width), spacing: 10), count: max(model.columns, 1)), spacing: 10) {
                    ForEach(Array(model.entries.enumerated()), id: \.element.id) { index, entry in
                        SwitcherTile(entry: entry, image: entry.windowID.flatMap { model.thumbnails[$0] },
                                     selected: index == model.selection, previews: model.previews, size: model.tile)
                            .contentShape(Rectangle())
                            .onTapGesture { pick(index) }
                            .onHover { inside in if inside { hover(index) } }
                    }
                }
                .animation(.spring(response: 0.22, dampingFraction: 0.86), value: model.selection)
            }
            HStack(spacing: 14) {
                hint("⇥", SwitcherPhrases.next.text)
                hint("W", SwitcherPhrases.close.text)
                hint("M", SwitcherPhrases.minimize.text)
                hint("H", SwitcherPhrases.hide.text)
                hint("Q", SwitcherPhrases.quit.text)
                hint("⎋", Phrases.cancel.text)
            }
            .frame(height: 16)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func hint(_ key: String, _ text: String) -> some View {
        HStack(spacing: 4) {
            Text(key).font(.system(size: 9.5, weight: .bold, design: .rounded)).foregroundStyle(Palette.ink)
                .frame(minWidth: 16, minHeight: 15)
                .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.white.opacity(0.1)))
            Text(text).font(.system(size: 10.5)).foregroundStyle(Palette.tertiary)
        }
    }
}

private struct SwitcherTile: View {
    let entry: WindowEntry
    let image: NSImage?
    let selected: Bool
    let previews: Bool
    let size: CGSize

    var body: some View {
        VStack(spacing: previews ? 6 : 8) {
            ZStack(alignment: .bottomLeading) {
                if previews {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.black.opacity(0.28))
                        if let image {
                            Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .shadow(color: .black.opacity(0.35), radius: 6, y: 3)
                                .padding(6)
                                .transition(.opacity)
                        } else {
                            AppIconView(path: entry.appPath, size: min(size.height * 0.42, 64), fallback: "macwindow")
                                .opacity(entry.minimized || entry.hidden ? 0.6 : 1)
                        }
                    }
                    .frame(width: size.width - 12, height: size.height - 44)
                    AppIconView(path: entry.appPath, size: 30, fallback: "app")
                        .shadow(color: .black.opacity(0.5), radius: 4, y: 2)
                        .offset(x: -4, y: 8)
                } else {
                    AppIconView(path: entry.appPath, size: min(size.width * 0.56, 76), fallback: "app")
                        .frame(width: size.width - 12, height: size.height - 52)
                }
            }
            HStack(spacing: 4) {
                if entry.minimized {
                    Image(systemName: "minus.circle.fill").font(.system(size: 9.5)).foregroundStyle(Palette.warning)
                } else if entry.hidden {
                    Image(systemName: "eye.slash.fill").font(.system(size: 9)).foregroundStyle(Palette.tertiary)
                } else if !entry.isWindow {
                    Image(systemName: "circle.dashed").font(.system(size: 9)).foregroundStyle(Palette.tertiary)
                }
                Text(entry.label)
                    .font(.system(size: 11.5, weight: selected ? .semibold : .medium))
                    .foregroundStyle(selected ? Palette.ink : Palette.secondary)
                    .lineLimit(previews ? 1 : 2)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 8)
            .frame(width: size.width - 8, height: previews ? 16 : 30)
        }
        .frame(width: size.width, height: size.height)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(selected ? Color.white.opacity(0.13) : Color.clear)
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(selected ? Palette.accent.opacity(0.9) : Color.clear, lineWidth: 1.6))
        }
        .scaleEffect(selected ? 1.02 : 1)
    }
}

enum SwitcherPhrases {
    static let next = Phrase("next", ru: "дальше", uk: "далі", fr: "suivant")
    static let close = Phrase("close", ru: "закрыть", uk: "закрити", fr: "fermer")
    static let minimize = Phrase("minimize", ru: "свернуть", uk: "згорнути", fr: "réduire")
    static let hide = Phrase("hide", ru: "скрыть", uk: "сховати", fr: "masquer")
    static let quit = Phrase("quit", ru: "выйти", uk: "вийти", fr: "quitter")
}
