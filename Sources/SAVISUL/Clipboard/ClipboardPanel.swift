import AppKit
import Carbon.HIToolbox
import Observation
import SwiftUI

@MainActor
@Observable
final class ClipboardBrowser {
    enum Filter: String, CaseIterable, Identifiable {
        case all, text, images, files, links, pinned
        var id: String { rawValue }
        var title: Phrase {
            switch self {
            case .all: return Phrase("All", ru: "Всё", uk: "Усе", fr: "Tout")
            case .text: return Phrase("Text", ru: "Текст", uk: "Текст", fr: "Texte")
            case .images: return Phrase("Images", ru: "Картинки", uk: "Зображення", fr: "Images")
            case .files: return Phrase("Files", ru: "Файлы", uk: "Файли", fr: "Fichiers")
            case .links: return Phrase("Links", ru: "Ссылки", uk: "Посилання", fr: "Liens")
            case .pinned: return Phrase("Pinned", ru: "Закреплённые", uk: "Закріплені", fr: "Épinglés")
            }
        }
    }

    var query = "" { didSet { selection = 0 } }
    var filter: Filter = .all { didSet { selection = 0 } }
    var selection = 0
    let history: ClipboardHistory

    init(history: ClipboardHistory) { self.history = history }

    var visible: [ClipItem] {
        let words = query.lowercased().split(separator: " ").map(String.init)
        let base = history.items.filter { item in
            switch filter {
            case .all: return true
            case .text: return item.kind == .text || item.kind == .color
            case .images: return item.kind == .image
            case .files: return item.kind == .files
            case .links: return item.kind == .link
            case .pinned: return item.pinned
            }
        }
        let matched = words.isEmpty ? base : base.filter { item in
            let haystack = [item.text ?? "", (item.files ?? []).joined(separator: " "), item.appName ?? ""].joined(separator: " ").lowercased()
            return words.allSatisfy { haystack.contains($0) }
        }
        guard filter == .all, words.isEmpty else { return Array(matched.prefix(400)) }
        return Array((matched.filter(\.pinned) + matched.filter { !$0.pinned }).prefix(400))
    }

    var current: ClipItem? {
        let list = visible
        return list.indices.contains(selection) ? list[selection] : list.first
    }
}

/// ⌃⌥V: search the history, preview, paste with or without formatting.
@MainActor
final class ClipboardPanel {
    private let browser: ClipboardBrowser
    private var panel: OverlayPanel?
    private var monitor: Any?
    private(set) var isOpen = false
    private static let size = NSSize(width: 780, height: 500)

    init(history: ClipboardHistory) {
        browser = ClipboardBrowser(history: history)
    }

    func toggle() { isOpen ? close() : open() }

    func open() {
        guard !isOpen else { return }
        isOpen = true
        browser.query = ""
        browser.filter = .all
        browser.selection = 0
        let panel = self.panel ?? make()
        Glass.fadeIn(panel, to: Glass.spotlightFrame(size: Self.size), lift: 10, key: true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            nonisolated(unsafe) let event = event
            let consumed = MainActor.assumeIsolated { Suite.shared.clipboard.panel.key(event) }
            return consumed ? nil : event
        }
    }

    func close() {
        guard isOpen else { return }
        isOpen = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if let panel { Glass.fadeOut(panel) }
    }

    private func make() -> OverlayPanel {
        let panel = OverlayPanel(size: Self.size, key: true, level: NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.popUpMenuWindow)) + 1))
        panel.onResignKey = { [weak self] in self?.close() }
        let view = ClipboardView(browser: browser, paste: { [weak self] item, plain in self?.paste(item, plain: plain) })
        panel.contentView = Glass.host(view, size: Self.size, radius: 24)
        self.panel = panel
        return panel
    }

    private func paste(_ item: ClipItem, plain: Bool) {
        close()
        browser.history.paste(item, plain: plain)
    }

    /// Returns true when the key was used here.
    fileprivate func key(_ event: NSEvent) -> Bool {
        guard isOpen, event.window === panel else { return false }
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let list = browser.visible
        switch Int(event.keyCode) {
        case kVK_DownArrow:
            browser.selection = min(browser.selection + 1, max(list.count - 1, 0))
            return true
        case kVK_UpArrow:
            browser.selection = max(browser.selection - 1, 0)
            return true
        case kVK_Return, kVK_ANSI_KeypadEnter:
            if let item = browser.current { paste(item, plain: flags.contains(.shift)) }
            return true
        case kVK_Escape:
            if browser.query.isEmpty { close() } else { browser.query = "" }
            return true
        case kVK_Tab:
            let all = ClipboardBrowser.Filter.allCases
            let index = all.firstIndex(of: browser.filter) ?? 0
            browser.filter = all[(index + (flags.contains(.shift) ? all.count - 1 : 1)) % all.count]
            return true
        case kVK_Delete where flags == .command:
            if let item = browser.current { browser.history.remove(item) }
            return true
        case kVK_ANSI_P where flags == .command:
            if let item = browser.current { browser.history.togglePin(item) }
            return true
        default:
            break
        }
        if flags == .command, let digit = Int(event.charactersIgnoringModifiers ?? ""), (1...9).contains(digit), list.count >= digit {
            paste(list[digit - 1], plain: false)
            return true
        }
        return false
    }
}

private struct ClipboardView: View {
    let browser: ClipboardBrowser
    let paste: (ClipItem, Bool) -> Void
    @FocusState private var focused: Bool

    var body: some View {
        let list = browser.visible
        HStack(spacing: 0) {
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.secondary)
                    TextField(ClipPhrases.search.text, text: Binding(get: { browser.query }, set: { browser.query = $0 }))
                        .textFieldStyle(.plain)
                        .font(.system(size: 16, weight: .medium))
                        .focused($focused)
                    Text("\(browser.history.items.count)").font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Palette.tertiary)
                }
                .padding(.horizontal, 12)
                .frame(height: 40)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.black.opacity(0.22)))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(ClipboardBrowser.Filter.allCases) { filter in
                            Button { browser.filter = filter } label: {
                                Text(filter.title.text).font(.system(size: 11.5, weight: browser.filter == filter ? .semibold : .medium))
                                    .foregroundStyle(browser.filter == filter ? Palette.onLight : Palette.secondary)
                                    .padding(.horizontal, 10).frame(height: 24)
                                    .background(Capsule().fill(browser.filter == filter ? Palette.ink : Color.white.opacity(0.06)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(list.enumerated()), id: \.element.id) { index, item in
                                ClipRow(item: item, history: browser.history, selected: index == browser.selection, shortcut: index < 9 ? index + 1 : nil)
                                    .id(item.id)
                                    .onTapGesture(count: 2) { paste(item, false) }
                                    .onTapGesture { browser.selection = index }
                            }
                        }
                    }
                    .onChange(of: browser.selection) { _, selection in
                        guard list.indices.contains(selection) else { return }
                        withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(list[selection].id, anchor: nil) }
                    }
                }
                if list.isEmpty {
                    Spacer()
                    VStack(spacing: 6) {
                        Image(systemName: "doc.on.clipboard").font(.system(size: 26, weight: .light)).foregroundStyle(Palette.tertiary)
                        Text(ClipPhrases.empty.text).font(.system(size: 12.5)).foregroundStyle(Palette.secondary)
                    }
                    Spacer()
                }
            }
            .padding(14)
            .frame(width: 340)
            Rectangle().fill(Palette.hairline).frame(width: 1)
            ClipPreview(item: browser.current, history: browser.history, paste: paste)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { focused = true }
    }
}

private struct ClipRow: View {
    let item: ClipItem
    let history: ClipboardHistory
    let selected: Bool
    let shortcut: Int?

    var body: some View {
        HStack(spacing: 10) {
            ClipIcon(item: item, history: history, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title.isEmpty ? " " : item.title)
                    .font(.system(size: 12.5, weight: .medium)).foregroundStyle(Palette.ink).lineLimit(1)
                HStack(spacing: 4) {
                    if item.pinned { Image(systemName: "pin.fill").font(.system(size: 8.5)).foregroundStyle(Palette.accent) }
                    Text([item.appName, Say.ago(item.date)].compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 10.5)).foregroundStyle(Palette.tertiary).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if let shortcut {
                Text("⌘\(shortcut)").font(.system(size: 10, weight: .semibold, design: .rounded)).foregroundStyle(Palette.tertiary)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 46)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(selected ? Color.white.opacity(0.12) : Color.clear))
        .contentShape(Rectangle())
    }
}

struct ClipIcon: View {
    let item: ClipItem
    let history: ClipboardHistory
    var size: CGFloat = 30

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.26, style: .continuous).fill(Color.white.opacity(0.07))
            switch item.kind {
            case .image:
                if let image = history.image(item) {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                        .frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
                } else {
                    Image(systemName: "photo").font(.system(size: size * 0.42)).foregroundStyle(Palette.secondary)
                }
            case .files:
                if let path = item.files?.first {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable().frame(width: size * 0.9, height: size * 0.9)
                }
            case .color:
                RoundedRectangle(cornerRadius: size * 0.22, style: .continuous).fill(ClipColor.parse(item.text ?? "") ?? .gray)
                    .padding(size * 0.14)
            case .link:
                Image(systemName: "link").font(.system(size: size * 0.42, weight: .semibold)).foregroundStyle(Palette.accent)
            case .text:
                Image(systemName: "text.alignleft").font(.system(size: size * 0.4, weight: .semibold)).foregroundStyle(Palette.secondary)
            }
        }
        .frame(width: size, height: size)
    }
}

private struct ClipPreview: View {
    let item: ClipItem?
    let history: ClipboardHistory
    let paste: (ClipItem, Bool) -> Void

    var body: some View {
        if let item {
            VStack(alignment: .leading, spacing: 12) {
                content(item)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                Rectangle().fill(Palette.hairline).frame(height: 1)
                HStack(spacing: 8) {
                    Text(meta(item)).font(.system(size: 11)).foregroundStyle(Palette.tertiary).lineLimit(1)
                    Spacer(minLength: 6)
                    PillButton(title: item.pinned ? ClipPhrases.unpin.text : ClipPhrases.pin.text, symbol: item.pinned ? "pin.slash" : "pin") {
                        history.togglePin(item)
                    }
                    if item.kind == .text && item.rich != nil {
                        PillButton(title: ClipPhrases.plain.text, symbol: "textformat") { paste(item, true) }
                    }
                    PillButton(title: ClipPhrases.paste.text, symbol: "return", prominent: true) { paste(item, false) }
                }
            }
            .padding(16)
        } else {
            VStack(spacing: 8) {
                KeyCaps(keys: ["⌘", "C"], size: 26)
                Text(ClipPhrases.hint.text).font(.system(size: 12.5)).foregroundStyle(Palette.secondary).multilineTextAlignment(.center)
            }
            .padding(30)
        }
    }

    @ViewBuilder
    private func content(_ item: ClipItem) -> some View {
        switch item.kind {
        case .image:
            if let image = history.image(item) {
                Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .files:
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if let first = item.files?.first { FileHero(path: first) }
                    ForEach(item.files ?? [], id: \.self) { path in
                        HStack(spacing: 8) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable().frame(width: 20, height: 20)
                            Text((path as NSString).lastPathComponent).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Palette.ink).lineLimit(1)
                            Spacer(minLength: 4)
                            Text((path as NSString).deletingLastPathComponent.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                                .font(.system(size: 10.5)).foregroundStyle(Palette.tertiary).lineLimit(1).truncationMode(.head)
                        }
                    }
                }
            }
        case .color:
            let color = ClipColor.parse(item.text ?? "") ?? .gray
            VStack(alignment: .leading, spacing: 12) {
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(color).frame(height: 180)
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(0.15), lineWidth: 1))
                Text(item.text ?? "").font(.system(size: 20, weight: .semibold, design: .monospaced)).foregroundStyle(Palette.ink).textSelection(.enabled)
            }
        case .link:
            VStack(alignment: .leading, spacing: 10) {
                Text(URL(string: item.text ?? "")?.host ?? "").font(.system(size: 18, weight: .semibold)).foregroundStyle(Palette.ink)
                Text(item.text ?? "").font(.system(size: 12.5)).foregroundStyle(Palette.accent).textSelection(.enabled).lineLimit(6)
                PillButton(title: Phrases.open.text, symbol: "safari") {
                    if let url = URL(string: item.text ?? "") { NSWorkspace.shared.open(url) }
                }
            }
        case .text:
            ScrollView {
                Text(item.text ?? "")
                    .font(.system(size: 13, design: looksLikeCode(item.text ?? "") ? .monospaced : .default))
                    .foregroundStyle(Palette.ink)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func looksLikeCode(_ text: String) -> Bool {
        let markers = ["{", "}", ";", "=>", "func ", "let ", "const ", "def ", "import ", "</"]
        return markers.filter { text.contains($0) }.count >= 2
    }

    private func meta(_ item: ClipItem) -> String {
        var parts: [String] = []
        if let app = item.appName { parts.append(app) }
        parts.append(Say.ago(item.date))
        if let text = item.text, item.kind == .text {
            parts.append(ClipPhrases.characters(item.longText ? history.fullText(item).count : text.count))
        }
        return parts.joined(separator: " · ")
    }
}

private struct FileHero: View {
    let path: String
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable().frame(width: 96, height: 96)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: 220)
        .task(id: path) { image = await Thumbnails.shared.thumbnail(path: path, size: 420) }
    }
}

enum ClipColor {
    static func parse(_ text: String) -> Color? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("rgb") {
            let numbers = trimmed.components(separatedBy: CharacterSet(charactersIn: "0123456789.").inverted).compactMap(Double.init)
            guard numbers.count >= 3 else { return nil }
            return Color(red: numbers[0] / 255, green: numbers[1] / 255, blue: numbers[2] / 255, opacity: numbers.count > 3 ? numbers[3] : 1)
        }
        var hex = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        if hex.count == 3 { hex = hex.map { "\($0)\($0)" }.joined() }
        guard hex.count == 6 || hex.count == 8, let value = UInt64(hex, radix: 16) else { return nil }
        let hasAlpha = hex.count == 8
        let r = Double((value >> (hasAlpha ? 24 : 16)) & 0xff) / 255
        let g = Double((value >> (hasAlpha ? 16 : 8)) & 0xff) / 255
        let b = Double((value >> (hasAlpha ? 8 : 0)) & 0xff) / 255
        let a = hasAlpha ? Double(value & 0xff) / 255 : 1
        return Color(red: r, green: g, blue: b, opacity: a)
    }
}

enum ClipPhrases {
    static let search = Phrase("Search the clipboard", ru: "Поиск по буферу", uk: "Пошук у буфері", fr: "Rechercher dans le presse-papiers")
    static let empty = Phrase("Nothing here yet", ru: "Пока пусто", uk: "Поки порожньо", fr: "Rien pour l’instant")
    static let hint = Phrase("Copy anything — it will be here, up to 1000 entries.",
                             ru: "Скопируйте что угодно — оно появится здесь, до 1000 записей.",
                             uk: "Скопіюйте будь-що — воно з’явиться тут, до 1000 записів.",
                             fr: "Copiez ce que vous voulez — jusqu’à 1000 éléments.")
    static let paste = Phrase("Paste", ru: "Вставить", uk: "Вставити", fr: "Coller")
    static let plain = Phrase("Plain", ru: "Без форматирования", uk: "Без форматування", fr: "Texte brut")
    static let pin = Phrase("Pin", ru: "Закрепить", uk: "Закріпити", fr: "Épingler")
    static let unpin = Phrase("Unpin", ru: "Открепить", uk: "Відкріпити", fr: "Désépingler")
    @MainActor static func characters(_ count: Int) -> String {
        Phrase("%d characters", ru: "Символов: %d", uk: "Символів: %d", fr: "%d caractères")(count)
    }
}

extension ClipboardPanel {
    /// Panel renders (--dump-panels): the ⌃⌥V panel over a sample history held in memory, written as panels-clipboard.png.
    static func dump(to folder: URL, completion: @escaping () -> Void) {
        let history = ClipboardHistory()
        history.preview(ClipSamples.items())
        let browser = ClipboardBrowser(history: history)
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        let content = ZStack {
            LinearGradient(colors: [Color(red: 0.17, green: 0.19, blue: 0.24), Color(red: 0.09, green: 0.09, blue: 0.11)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            shape.fill(Color(red: 0.05, green: 0.05, blue: 0.06).opacity(0.6))
            shape.fill(RadialGradient(colors: [Color.white.opacity(0.09), .clear], center: UnitPoint(x: 0.18, y: 0), startRadius: 0, endRadius: 340))
            ClipboardView(browser: browser, paste: { _, _ in })
            shape.strokeBorder(LinearGradient(colors: [Color.white.opacity(0.3), Color.white.opacity(0.06), Color.white.opacity(0.14)],
                                              startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
        }
        .clipShape(shape)
        .frame(width: size.width, height: size.height)
        .environment(\.colorScheme, .dark)
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -4000, y: -4000), size: size), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = NSHostingView(rootView: content)
        window.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            MainActor.assumeIsolated {
                if let view = window.contentView {
                    view.layoutSubtreeIfNeeded()
                    if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                        view.cacheDisplay(in: view.bounds, to: bitmap)
                        try? bitmap.representation(using: .png, properties: [:])?.write(to: folder.appendingPathComponent("panels-clipboard.png"))
                    }
                }
                window.orderOut(nil)
                completion()
            }
        }
    }
}

/// The sample history the panel render shows: one of each kind, newest first, the colour pinned.
private enum ClipSamples {
    static func items() -> [ClipItem] {
        let now = Date()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("savisul-clipboard-render", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let deck = folder.appendingPathComponent("Launch Plan.pdf").path
        if !FileManager.default.fileExists(atPath: deck) { FileManager.default.createFile(atPath: deck, contents: Data()) }
        func clip(_ kind: ClipItem.Kind, _ text: String?, files: [String]? = nil, app: String, minutes: Double, pinned: Bool = false) -> ClipItem {
            ClipItem(kind: kind, text: text, files: files, appName: app, date: now.addingTimeInterval(-minutes * 60),
                     pinned: pinned, signature: UUID().uuidString)
        }
        return [
            clip(.color, "#DBC7A3", app: "Figma", minutes: 140, pinned: true),
            clip(.text, "Launch day, 9:41 — island polish, release notes, App Store screenshots", app: "Notes", minutes: 1),
            clip(.link, "https://developer.apple.com/design/human-interface-guidelines/materials", app: "Safari", minutes: 4),
            clip(.text, "let island = Island(height: 37)\nisland.expand(to: .agents, animated: true)", app: "Cursor", minutes: 9),
            clip(.files, nil, files: [deck], app: "Finder", minutes: 17),
            clip(.text, "Running 10 min late — grab us a table by the window", app: "Messages", minutes: 26),
            clip(.color, "#7A6CF0", app: "Figma", minutes: 38),
            clip(.text, "Invoice #2048 is paid — thank you!", app: "Mail", minutes: 55),
            clip(.link, "https://lrclib.net", app: "Safari", minutes: 72)
        ]
    }
}
