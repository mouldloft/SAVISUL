import AppKit
import Carbon.HIToolbox
import Observation
import SwiftUI

enum CommandSection: Int, CaseIterable {
    case answer, top, apps, windows, menu, actions, clipboard, files, emoji, web

    var title: Phrase {
        switch self {
        case .answer: return Phrase("Answer", ru: "Ответ", uk: "Відповідь", fr: "Réponse")
        case .top: return Phrase("Top hit", ru: "Лучшее совпадение", uk: "Найкращий збіг", fr: "Meilleur résultat")
        case .apps: return Phrase("Apps", ru: "Приложения", uk: "Застосунки", fr: "Apps")
        case .windows: return Phrase("Windows", ru: "Окна", uk: "Вікна", fr: "Fenêtres")
        case .menu: return Phrase("Menu of %@", ru: "Меню: %@", uk: "Меню: %@", fr: "Menu de %@")
        case .actions: return Phrase("SAVISUL", ru: "SAVISUL", uk: "SAVISUL", fr: "SAVISUL")
        case .clipboard: return Phrase("Clipboard", ru: "Буфер обмена", uk: "Буфер обміну", fr: "Presse-papiers")
        case .files: return Phrase("Files", ru: "Файлы", uk: "Файли", fr: "Fichiers")
        case .emoji: return Phrase("Emoji", ru: "Эмодзи", uk: "Емодзі", fr: "Émojis")
        case .web: return Phrase("Web", ru: "Интернет", uk: "Інтернет", fr: "Web")
        }
    }
}

enum CommandIcon {
    case path(String)
    case symbol(String, Color)
    case emoji(String)
    case clip(ClipItem)
    case image(NSImage)
}

struct CommandResult: Identifiable {
    let id: String
    var section: CommandSection
    let title: String
    var subtitle: String?
    let icon: CommandIcon
    var score: Double
    var trailing: String?
    let run: @MainActor () -> Void
    var reveal: (@MainActor () -> Void)?
    var copy: String?
}

@MainActor
@Observable
final class CommandModel {
    var query = ""
    var results: [CommandResult] = []
    var selection = 0
    var frontApp = ""
    var menuReady = false

    var selected: CommandResult? { results.indices.contains(selection) ? results[selection] : nil }
}

/// ⌥Space: apps, windows, the front app's menu commands, SAVISUL actions, clipboard, files,
/// a calculator, unit and currency conversion, emoji and web search in one field.
@MainActor
final class CommandBar {
    let model = CommandModel()
    let files = FileSearch()
    private var panel: OverlayPanel?
    private var monitor: Any?
    private(set) var isOpen = false
    private var frontPID: pid_t = 0
    private var menu: [MenuRecord] = []
    private var windows: [WindowEntry] = []
    private var fileResults: [URL] = []
    private var searchWork: DispatchWorkItem?
    private static let size = NSSize(width: 700, height: 470)

    init() {
        files.onResults = { [weak self] urls in
            self?.fileResults = urls
            self?.rebuild(keepSelection: true)
        }
    }

    func toggle() { isOpen ? close() : open() }

    func open() {
        guard !isOpen else { return }
        isOpen = true
        AppIndex.shared.refresh()
        let front = NSWorkspace.shared.frontmostApplication
        let me = ProcessInfo.processInfo.processIdentifier
        let target = front?.processIdentifier == me ? WindowCatalog.shared.previousApp : front
        frontPID = target?.processIdentifier ?? 0
        model.frontApp = target?.localizedName ?? ""
        model.query = ""
        model.selection = 0
        model.menuReady = false
        menu = []
        windows = []
        fileResults = []
        rebuild(keepSelection: false)
        let panel = self.panel ?? make()
        Glass.fadeIn(panel, to: Glass.spotlightFrame(size: Self.size), lift: 10, key: true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            nonisolated(unsafe) let event = event
            let consumed = MainActor.assumeIsolated { Suite.shared.commands.bar.key(event) }
            return consumed ? nil : event
        }
        let pid = frontPID
        if pid > 0, AX.trusted {
            Task.detached(priority: .userInitiated) {
                let items = MenuIndex.collect(pid)
                await MainActor.run {
                    let bar = Suite.shared.commands.bar
                    guard bar.isOpen, bar.frontPID == pid else { return }
                    bar.menu = items
                    bar.model.menuReady = true
                    bar.rebuild(keepSelection: true)
                }
            }
        }
        Task { @MainActor in
            let entries = await WindowCatalog.shared.entries(includeEmptyApps: false)
            guard self.isOpen else { return }
            self.windows = entries
            self.rebuild(keepSelection: true)
        }
    }

    func close() {
        guard isOpen else { return }
        isOpen = false
        files.stop()
        searchWork?.cancel()
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if let panel { Glass.fadeOut(panel) }
    }

    private func make() -> OverlayPanel {
        let panel = OverlayPanel(size: Self.size, key: true, level: NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.popUpMenuWindow)) + 1))
        panel.onResignKey = { [weak self] in self?.close() }
        let view = CommandView(model: model, queryChanged: { [weak self] in self?.queryChanged() },
                               run: { [weak self] result in self?.execute(result) })
        panel.contentView = Glass.host(view, size: Self.size, radius: 24)
        self.panel = panel
        return panel
    }

    func ratesArrived() {
        if isOpen { rebuild(keepSelection: true) }
    }

    private func queryChanged() {
        model.selection = 0
        rebuild(keepSelection: false)
        searchWork?.cancel()
        let query = model.query
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.isOpen else { return }
                self.fileResults = []
                self.files.search(query)
            }
        }
        searchWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: work)
    }

    private func execute(_ result: CommandResult) {
        close()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { MainActor.assumeIsolated { result.run() } }
    }

    fileprivate func key(_ event: NSEvent) -> Bool {
        guard isOpen, event.window === panel else { return false }
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        switch Int(event.keyCode) {
        case kVK_DownArrow:
            model.selection = min(model.selection + 1, max(model.results.count - 1, 0))
            return true
        case kVK_UpArrow:
            model.selection = max(model.selection - 1, 0)
            return true
        case kVK_Return, kVK_ANSI_KeypadEnter:
            guard let result = model.selected else { return true }
            if flags.contains(.command), let reveal = result.reveal {
                close()
                reveal()
            } else {
                execute(result)
            }
            return true
        case kVK_Escape:
            if model.query.isEmpty { close() } else { model.query = ""; queryChanged() }
            return true
        case kVK_ANSI_C where flags == .command:
            guard let text = model.selected?.copy else { return false }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            close()
            Suite.shared.notify(IslandNotice(symbol: "doc.on.doc.fill", tint: Palette.accent, title: Phrases.copy.text, detail: text, duration: 1.8))
            return true
        default:
            break
        }
        if flags == .command, let digit = Int(event.charactersIgnoringModifiers ?? ""), (1...9).contains(digit), model.results.count >= digit {
            execute(model.results[digit - 1])
            return true
        }
        return false
    }

    // MARK: Results

    private func rebuild(keepSelection: Bool) {
        let previous = model.selected?.id
        let query = model.query.trimmingCharacters(in: .whitespaces)
        var list = query.isEmpty ? suggestions() : search(query)
        if list.isEmpty, let other = Fuzzy.otherLayout(query) { list = search(other) }
        model.results = list
        if keepSelection, let previous, let index = list.firstIndex(where: { $0.id == previous }) {
            model.selection = index
        } else {
            model.selection = 0
        }
    }

    private func suggestions() -> [CommandResult] {
        var out: [CommandResult] = []
        let running = RunningApps.regular().prefix(6)
        for app in running {
            guard let path = app.bundleURL?.path else { continue }
            out.append(CommandResult(id: "run:\(path)", section: .apps, title: app.localizedName ?? "", subtitle: nil, icon: .path(path), score: 50,
                                     trailing: nil, run: { Self.launch(path) }, reveal: { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }))
        }
        for id in Suite.shared.settings.favorites.prefix(6) {
            guard let action = SuiteActions.action(id), id != "command.open" else { continue }
            out.append(actionResult(action, score: 40))
        }
        for item in Suite.shared.clipboard.history.items.prefix(3) {
            out.append(clipResult(item, score: 30))
        }
        return out
    }

    private func search(_ query: String) -> [CommandResult] {
        var buckets: [CommandSection: [CommandResult]] = [:]
        func put(_ result: CommandResult) { buckets[result.section, default: []].append(result) }

        if let value = Calculator.evaluate(query) {
            let text = Calculator.format(value)
            put(CommandResult(id: "calc", section: .answer, title: "= \(text)", subtitle: query, icon: .symbol("equal.circle.fill", Palette.accent),
                              score: 200, trailing: "⌘C", run: { Self.copyText(text) }, copy: text))
        }
        if let converted = Converter.convert(query) {
            let output = converted.output
            put(CommandResult(id: "convert", section: .answer, title: output, subtitle: converted.input,
                              icon: .symbol(Converter.currencies.values.contains(where: { output.hasSuffix($0) }) ? "dollarsign.circle.fill" : "arrow.left.arrow.right.circle.fill", Palette.positive),
                              score: 199, trailing: "⌘C", run: { Self.copyText(output) }, copy: output))
        }

        let emojiQuery: String? = query.hasPrefix(":") ? String(query.dropFirst())
            : query.lowercased().hasPrefix("emoji ") ? String(query.dropFirst(6))
            : query.lowercased().hasPrefix("эмодзи ") ? String(query.dropFirst(7)) : nil
        if let emojiQuery {
            for (index, entry) in EmojiIndex.search(emojiQuery).enumerated() {
                let emoji = entry.emoji
                put(CommandResult(id: "emoji:\(emoji)", section: .emoji, title: entry.name.capitalized, subtitle: nil, icon: .emoji(emoji),
                                  score: 150 - Double(index), trailing: nil, run: { Self.insert(emoji) }, copy: emoji))
            }
        }

        let runningPaths = Set(RunningApps.regular().compactMap { $0.bundleURL?.path })
        for app in AppIndex.shared.apps {
            let score = max(Fuzzy.score(app.name, query) ?? 0, (Fuzzy.score(app.fileName, query) ?? 0) - 2)
            guard score > 0 else { continue }
            let path = app.path
            put(CommandResult(id: "app:\(path)", section: .apps, title: app.name, subtitle: runningPaths.contains(path) ? CommandPhrases.running.text : nil,
                              icon: .path(path), score: score + (runningPaths.contains(path) ? 3 : 0), trailing: nil,
                              run: { Self.launch(path) }, reveal: { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }))
        }

        for entry in windows where entry.isWindow && !entry.title.isEmpty {
            let score = max(Fuzzy.score(entry.title, query) ?? 0, (Fuzzy.score(entry.appName, query) ?? 0) - 25)
            guard score > 0 else { continue }
            put(CommandResult(id: "win:\(entry.id)", section: .windows, title: entry.title, subtitle: entry.appName,
                              icon: entry.appPath.map { CommandIcon.path($0) } ?? .symbol("macwindow", Palette.secondary),
                              score: score - 6, trailing: entry.minimized ? "—" : nil, run: { Switcher.activate(entry) }))
        }

        for (index, record) in menu.enumerated() where record.enabled {
            let score = max(Fuzzy.score(record.title, query) ?? 0, (Fuzzy.score(record.path.joined(separator: " "), query) ?? 0) - 10)
            guard score > 0 else { continue }
            let box = record.box
            put(CommandResult(id: "menu:\(index)", section: .menu, title: record.title,
                              subtitle: record.path.dropLast().joined(separator: " › "), icon: .symbol("filemenu.and.selection", Palette.accent),
                              score: score - 4, trailing: record.shortcut, run: { AX.perform(box.element, kAXPressAction) }))
        }

        for action in SuiteActions.all {
            let title = SuiteActions.title(action)
            let english = action.title.text(.en)
            var score = max(Fuzzy.score(title, query) ?? 0, Fuzzy.score(english, query) ?? 0)
            for keyword in action.keywords { score = max(score, (Fuzzy.score(keyword, query) ?? 0) - 8) }
            guard score > 0 else { continue }
            put(actionResult(action, score: score - 3))
        }

        let words = query.lowercased()
        var clips = 0
        for item in Suite.shared.clipboard.history.items where clips < 4 {
            let haystack = (item.kind == .files ? (item.files ?? []).joined(separator: " ") : item.text ?? "").lowercased()
            guard words.count >= 2, haystack.contains(words) else { continue }
            clips += 1
            put(clipResult(item, score: 45 - Double(clips)))
        }

        for (index, url) in fileResults.enumerated() {
            let path = url.path
            let name = url.lastPathComponent
            let score = (Fuzzy.score(name, query) ?? 30) - 10 - Double(index) * 0.5
            put(CommandResult(id: "file:\(path)", section: .files, title: name,
                              subtitle: url.deletingLastPathComponent().path.replacingOccurrences(of: NSHomeDirectory(), with: "~"),
                              icon: .path(path), score: score, trailing: nil,
                              run: { NSWorkspace.shared.open(url) }, reveal: { NSWorkspace.shared.activateFileViewerSelecting([url]) }))
        }

        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        if let url = Self.webAddress(query) {
            put(CommandResult(id: "open-url", section: .web, title: CommandPhrases.openSite(url.host ?? query), subtitle: url.absoluteString,
                              icon: .symbol("safari.fill", Palette.accent), score: 1, trailing: nil, run: { NSWorkspace.shared.open(url) }))
        }
        if let google = URL(string: "https://www.google.com/search?q=\(encoded)") {
            put(CommandResult(id: "web", section: .web, title: CommandPhrases.searchWeb(query), subtitle: "Google",
                              icon: .symbol("magnifyingglass.circle.fill", Palette.secondary), score: 0, trailing: nil, run: { NSWorkspace.shared.open(google) }))
        }

        let limits: [CommandSection: Int] = [.answer: 2, .apps: 6, .windows: 5, .menu: 6, .actions: 5, .clipboard: 4, .files: 8, .emoji: 12, .web: 2]
        var sections: [(CommandSection, [CommandResult])] = []
        for (section, items) in buckets {
            sections.append((section, Array(items.sorted { $0.score > $1.score }.prefix(limits[section] ?? 5))))
        }
        var flat: [CommandResult] = []
        if let answer = sections.first(where: { $0.0 == .answer }) { flat += answer.1 }
        let middle = sections.filter { $0.0 != .answer && $0.0 != .web }.sorted { ($0.1.first?.score ?? 0) > ($1.1.first?.score ?? 0) }
        if flat.isEmpty, var first = middle.first?.1.first, first.score >= 70 {
            first.section = .top
            flat.append(first)
            for (section, items) in middle {
                flat += items.filter { $0.id != first.id }.map { item in
                    var copy = item
                    copy.section = section
                    return copy
                }
            }
        } else {
            for (_, items) in middle { flat += items }
        }
        if let web = sections.first(where: { $0.0 == .web }) { flat += web.1 }
        return flat
    }

    private func actionResult(_ action: SuiteAction, score: Double) -> CommandResult {
        let run = action.run
        return CommandResult(id: "act:\(action.id)", section: .actions, title: SuiteActions.title(action), subtitle: nil,
                             icon: .symbol(action.symbol, action.tint), score: score, trailing: nil, run: run)
    }

    private func clipResult(_ item: ClipItem, score: Double) -> CommandResult {
        CommandResult(id: "clip:\(item.id)", section: .clipboard, title: item.title, subtitle: [item.appName, Say.ago(item.date)].compactMap { $0 }.joined(separator: " · "),
                      icon: .clip(item), score: score, trailing: nil, run: { Suite.shared.clipboard.history.paste(item, plain: false) })
    }

    private static func webAddress(_ query: String) -> URL? {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.contains(" "), trimmed.contains("."), trimmed.range(of: #"^[\w.-]+\.[a-zа-я]{2,}(/.*)?$"#, options: [.regularExpression, .caseInsensitive]) != nil
                || trimmed.hasPrefix("http") else { return nil }
        return URL(string: trimmed.hasPrefix("http") ? trimmed : "https://\(trimmed)")
    }

    static func launch(_ path: String) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: configuration)
    }

    private static func copyText(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        Suite.shared.notify(IslandNotice(symbol: "doc.on.doc.fill", tint: Palette.accent, title: Phrases.copy.text, detail: text, duration: 1.8))
    }

    /// Types the emoji into the app in front by way of the clipboard, then restores the clipboard.
    private static func insert(_ text: String) {
        let item = ClipItem(kind: .text, text: text, date: Date(), signature: "emoji")
        Suite.shared.clipboard.history.write(item, plain: true)
        Keys.whenModifiersReleased { Keys.paste() }
    }
}

private struct CommandView: View {
    let model: CommandModel
    let queryChanged: () -> Void
    let run: (CommandResult) -> Void
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass").font(.system(size: 19, weight: .semibold)).foregroundStyle(Palette.accent)
                TextField(CommandPhrases.placeholder.text, text: Binding(get: { model.query }, set: { model.query = $0; queryChanged() }))
                    .textFieldStyle(.plain)
                    .font(.system(size: 21, weight: .medium))
                    .focused($focused)
                if !model.frontApp.isEmpty {
                    HStack(spacing: 4) {
                        if !model.menuReady && AX.trusted { Spinner(size: 10, color: Palette.tertiary) }
                        Text(model.frontApp).font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.tertiary).lineLimit(1)
                    }
                    .padding(.horizontal, 8).frame(height: 22)
                    .background(Capsule().fill(Color.white.opacity(0.06)))
                }
            }
            .padding(.horizontal, 20)
            .frame(height: 62)
            Rectangle().fill(Palette.hairline).frame(height: 1)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(model.results.enumerated()), id: \.element.id) { index, result in
                            if index == 0 || model.results[index - 1].section != result.section {
                                Text(sectionTitle(result.section))
                                    .font(.system(size: 10.5, weight: .semibold)).foregroundStyle(Palette.tertiary)
                                    .textCase(.uppercase)
                                    .padding(.horizontal, 12).padding(.top, index == 0 ? 6 : 10).padding(.bottom, 3)
                            }
                            CommandRow(result: result, selected: index == model.selection, shortcut: index < 9 ? index + 1 : nil)
                                .id(result.id)
                                .onTapGesture { run(result) }
                        }
                    }
                    .padding(8)
                }
                .onChange(of: model.selection) { _, selection in
                    guard model.results.indices.contains(selection) else { return }
                    proxy.scrollTo(model.results[selection].id, anchor: nil)
                }
            }
            Rectangle().fill(Palette.hairline).frame(height: 1)
            HStack(spacing: 14) {
                hint("↩", CommandPhrases.open.text)
                hint("⌘↩", Phrases.reveal.text)
                hint("⌘C", Phrases.copy.text)
                hint("⌘1–9", CommandPhrases.quick.text)
                Spacer()
                Text(CommandPhrases.tips.text).font(.system(size: 10.5)).foregroundStyle(Palette.tertiary).lineLimit(1)
            }
            .padding(.horizontal, 16)
            .frame(height: 34)
        }
        .onAppear { focused = true }
    }

    private func sectionTitle(_ section: CommandSection) -> String {
        section == .menu ? section.title(model.frontApp) : section.title.text
    }

    private func hint(_ key: String, _ text: String) -> some View {
        HStack(spacing: 4) {
            Text(key).font(.system(size: 10, weight: .bold, design: .rounded)).foregroundStyle(Palette.ink)
            Text(text).font(.system(size: 10.5)).foregroundStyle(Palette.tertiary)
        }
    }
}

private struct CommandRow: View {
    let result: CommandResult
    let selected: Bool
    let shortcut: Int?

    var body: some View {
        HStack(spacing: 12) {
            icon.frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(result.title)
                    .font(.system(size: result.section == .answer ? 17 : 13.5, weight: result.section == .answer ? .semibold : .medium,
                                  design: result.section == .answer ? .rounded : .default))
                    .foregroundStyle(Palette.ink).lineLimit(1)
                if let subtitle = result.subtitle, !subtitle.isEmpty {
                    Text(subtitle).font(.system(size: 11)).foregroundStyle(Palette.tertiary).lineLimit(1).truncationMode(.middle)
                }
            }
            Spacer(minLength: 8)
            if let trailing = result.trailing {
                Text(trailing).font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(Palette.secondary)
            }
            if let shortcut, selected || result.section == .answer {
                Text("⌘\(shortcut)").font(.system(size: 10, weight: .semibold, design: .rounded)).foregroundStyle(Palette.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: result.subtitle == nil ? 40 : 46)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(selected ? Color.white.opacity(0.12) : Color.clear))
        .contentShape(Rectangle())
    }

    @ViewBuilder private var icon: some View {
        switch result.icon {
        case .path(let path):
            AppIconView(path: path, size: 28, fallback: "doc")
        case .symbol(let name, let tint):
            Image(systemName: name).font(.system(size: 14, weight: .semibold)).foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(tint.opacity(0.14)))
        case .emoji(let emoji):
            Text(emoji).font(.system(size: 22))
        case .clip(let item):
            ClipIcon(item: item, history: Suite.shared.clipboard.history, size: 28)
        case .image(let image):
            Image(nsImage: image).resizable().frame(width: 28, height: 28)
        }
    }
}

enum CommandPhrases {
    static let placeholder = Phrase("Apps, windows, menus, files, 2+2, 10 km in mi…",
                                    ru: "Приложения, окна, меню, файлы, 2+2, 100 $ в рублях…",
                                    uk: "Застосунки, вікна, меню, файли, 2+2, 100 $ у гривнях…",
                                    fr: "Apps, fenêtres, menus, fichiers, 2+2, 10 km en mi…")
    static let running = Phrase("Running", ru: "Запущено", uk: "Запущено", fr: "Ouverte")
    static let open = Phrase("open", ru: "открыть", uk: "відкрити", fr: "ouvrir")
    static let quick = Phrase("quick pick", ru: "быстрый выбор", uk: "швидкий вибір", fr: "choix rapide")
    static let tips = Phrase(":fire for emoji", ru: ":fire — эмодзи", uk: ":fire — емодзі", fr: ":fire pour les émojis")
    @MainActor static func searchWeb(_ query: String) -> String {
        Phrase("Search the web for “%@”", ru: "Искать «%@» в интернете", uk: "Шукати «%@» в інтернеті", fr: "Rechercher « %@ » sur le web")(query)
    }
    @MainActor static func openSite(_ host: String) -> String {
        Phrase("Open %@", ru: "Открыть %@", uk: "Відкрити %@", fr: "Ouvrir %@")(host)
    }
}
