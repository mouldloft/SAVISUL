import AppKit
import Carbon.HIToolbox
import Observation
import SwiftUI

@MainActor
@Observable
final class ContextModel {
    enum Stage {
        case list
        case prompt(ActionDefinition)
        case running(ActionDefinition)
        case result(ActionDefinition, ActionOutput)
        case failed(ActionDefinition, String)
    }

    var context = ActionContext()
    var actions: [ActionDefinition] = []
    var filter = ""
    var selection = 0
    var stage: Stage = .list
    var input = ""
    /// The answer so far while an AI action writes it.
    var streamed = ""

    var visible: [ActionDefinition] {
        let needle = filter.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return actions }
        return actions.filter { action in
            action.title.text.lowercased().contains(needle) || action.keywords.contains { $0.lowercased().hasPrefix(needle) }
        }
    }

    var selected: ActionDefinition? { visible.indices.contains(selection) ? visible[selection] : nil }

    var stageID: String {
        switch stage {
        case .list: "list"
        case .prompt(let action): "prompt.\(action.id)"
        case .running(let action): "running.\(action.id)"
        case .result(let action, _): "result.\(action.id)"
        case .failed(let action, _): "failed.\(action.id)"
        }
    }

    /// The text the result shows: the finished answer, or what has streamed in so far.
    var resultText: String? {
        switch stage {
        case .running: streamed.isEmpty ? nil : streamed
        case .result(_, .text(let text)): text
        default: nil
        }
    }
}

/// ⌃⌥A: actions for whatever is selected in any app, or for what's on the clipboard when nothing is.
@MainActor
final class ContextActionsPanel: NSObject, NSSharingServicePickerDelegate {
    let model = ContextModel()
    private var panel: OverlayPanel?
    private var monitor: Any?
    private var clicks: Any?
    private var switching: NSObjectProtocol?
    private var current: ActionRun?
    fileprivate var sharing = false
    private(set) var isOpen = false
    private static let size = NSSize(width: 600, height: 440)

    func toggle() {
        if isOpen { close() } else { open() }
    }

    /// Reads the selection, then opens on it.
    func open() {
        guard !isOpen else { return }
        SelectionReader.read { [weak self] context in self?.open(with: context) }
    }

    /// Opens on a context someone else already has: a Shelf item, a file from the island.
    func open(with context: ActionContext) {
        model.context = context
        model.actions = ActionRegistry.actions(for: context)
        model.filter = ""
        model.selection = 0
        model.input = ""
        model.streamed = ""
        model.stage = .list
        guard !isOpen else { return }
        isOpen = true
        let panel = self.panel ?? make()
        Glass.fadeIn(panel, to: Glass.spotlightFrame(size: Self.size), lift: 10, key: true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            nonisolated(unsafe) let event = event
            let consumed = MainActor.assumeIsolated { Suite.shared.contextActions.key(event) }
            return consumed ? nil : event
        }
        // A click in another app or a switch to one closes the panel. Losing the keyboard alone doesn't:
        // macOS can hand it back to the app in front a moment after the selection was read.
        clicks = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { _ in
            MainActor.assumeIsolated {
                let panel = Suite.shared.contextActions
                if !panel.sharing { panel.close() }
            }
        }
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        switching = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { note in
            let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            MainActor.assumeIsolated {
                let panel = Suite.shared.contextActions
                if pid != front, pid != ProcessInfo.processInfo.processIdentifier, !panel.sharing { panel.close() }
            }
        }
    }

    func close() {
        guard isOpen else { return }
        isOpen = false
        current?.cancel()
        current = nil
        for watcher in [monitor, clicks] { if let watcher { NSEvent.removeMonitor(watcher) } }
        monitor = nil
        clicks = nil
        if let switching { NSWorkspace.shared.notificationCenter.removeObserver(switching) }
        switching = nil
        if let panel { Glass.fadeOut(panel) }
    }

    private func make() -> OverlayPanel {
        let panel = OverlayPanel(size: Self.size, key: true, level: NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.popUpMenuWindow)) + 1))
        panel.contentView = Glass.host(ContextView(model: model, panel: self), size: Self.size, radius: 24)
        self.panel = panel
        return panel
    }

    // MARK: Running

    func choose(_ action: ActionDefinition) {
        if case .list = model.stage, let prompt = action.prompt {
            model.input = prompt.initial?(model.context) ?? ""
            withAnimation(.panelSpring) { model.stage = .prompt(action) }
            return
        }
        run(action, input: model.input)
    }

    func submitPrompt() {
        guard case .prompt(let action) = model.stage else { return }
        run(action, input: model.input)
    }

    private func run(_ action: ActionDefinition, input: String?) {
        let context = model.context
        let handle = ActionRun(activity: action.activity.map { Suite.shared.live.start(symbol: action.symbol, tint: action.tint, title: $0.text) })
        handle.onText = { [weak self] text in self?.model.streamed = text }
        current = handle
        model.streamed = ""
        withAnimation(.panelSpring) { model.stage = .running(action) }
        Task { @MainActor in
            let result = await ActionEngine.execute(action, context: context, input: input, run: handle)
            guard current === handle else { return }
            current = nil
            switch result {
            case .success(let output):
                finish(action, output)
            case .failure(let error):
                guard isOpen else {
                    Suite.shared.notify(IslandNotice(symbol: "exclamationmark.triangle.fill", tint: Palette.warning, title: action.title.text,
                                                     detail: error.localizedDescription, style: .warning, duration: 4.5))
                    return
                }
                withAnimation(.panelSpring) { model.stage = .failed(action, error.localizedDescription) }
            }
        }
    }

    private func finish(_ action: ActionDefinition, _ output: ActionOutput) {
        switch output {
        case .none:
            close()
        case .notice(let text, let symbol):
            close()
            Suite.shared.notify(IslandNotice(symbol: symbol, tint: Palette.positive, title: text, detail: nil, style: .success, duration: 2))
        case .text, .files:
            if isOpen {
                withAnimation(.panelSpring) { model.stage = .result(action, output) }
            } else if case .files(let urls) = output {
                Suite.shared.notify(IslandNotice(symbol: "checkmark.circle.fill", tint: Palette.positive, title: action.title.text,
                                                 detail: urls.map(\.lastPathComponent).joined(separator: ", "), style: .success, duration: 3.5,
                                                 actionTitle: Phrases.reveal.text, action: { NSWorkspace.shared.activateFileViewerSelecting(urls) }))
            }
        }
    }

    func back() {
        current?.cancel()
        current = nil
        model.input = ""
        withAnimation(.panelSpring) { model.stage = .list }
    }

    // MARK: Results

    func copyResult() {
        guard let text = model.resultText else { return }
        Clipboard.copy(text)
        close()
        Suite.shared.notify(IslandNotice(symbol: "doc.on.doc.fill", tint: Palette.accent, title: Phrases.copy.text, detail: text, duration: 1.8))
    }

    /// Types the result into the app in front, replacing the selection.
    func pasteResult() {
        guard let text = model.resultText else { return }
        close()
        let item = ClipItem(kind: .text, text: text, date: Date(), signature: "context")
        Suite.shared.clipboard.history.write(item, plain: true)
        Keys.whenModifiersReleased { Keys.paste() }
    }

    func shelveResult() {
        if case .result(_, .files(let urls)) = model.stage {
            Suite.shared.shelf.add(urls: urls)
        } else if let text = model.resultText {
            Suite.shared.shelf.add(text: text)
        }
        close()
        Suite.shared.notify(IslandNotice(symbol: "tray.full.fill", tint: Palette.accent, title: Phrases.onShelf.text, detail: nil, duration: 1.6))
    }

    func openAISettings() {
        close()
        Suite.shared.app?.select(.settings)
        Suite.shared.app?.onShow?()
    }

    /// The system share sheet, anchored to the panel; the panel stays open until it's done.
    func share(_ items: [Any]) {
        guard let view = panel?.contentView, !items.isEmpty else { return }
        sharing = true
        let picker = NSSharingServicePicker(items: items)
        picker.delegate = self
        picker.show(relativeTo: NSRect(x: view.bounds.midX - 1, y: 40, width: 2, height: 2), of: view, preferredEdge: .minY)
    }

    nonisolated func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker, didChoose service: NSSharingService?) {
        MainActor.assumeIsolated {
            sharing = false
            close()
        }
    }

    // MARK: Keys

    fileprivate func key(_ event: NSEvent) -> Bool {
        guard isOpen, event.window === panel else { return false }
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let code = Int(event.keyCode)
        switch model.stage {
        case .list:
            switch code {
            case kVK_DownArrow:
                model.selection = min(model.selection + 1, max(model.visible.count - 1, 0))
                return true
            case kVK_UpArrow:
                model.selection = max(model.selection - 1, 0)
                return true
            case kVK_Return, kVK_ANSI_KeypadEnter:
                if let action = model.selected { choose(action) }
                return true
            case kVK_Escape:
                if model.filter.isEmpty { close() } else { model.filter = ""; model.selection = 0 }
                return true
            default:
                if flags == .command, let digit = Int(event.charactersIgnoringModifiers ?? ""), (1...9).contains(digit), model.visible.count >= digit {
                    choose(model.visible[digit - 1])
                    return true
                }
                return false
            }
        case .prompt:
            if code == kVK_Escape { back(); return true }
            return false
        case .running:
            if code == kVK_Escape { back(); return true }
            return false
        case .result, .failed:
            switch code {
            case kVK_Escape:
                close()
                return true
            case kVK_Return where flags == .command:
                pasteResult()
                return true
            case kVK_ANSI_C where flags == .command:
                // Copying a selection inside the answer still works; with none, ⌘C takes the whole answer.
                if let field = event.window?.firstResponder as? NSTextView, field.selectedRange().length > 0 { return false }
                copyResult()
                return true
            case kVK_Delete where flags.isEmpty, kVK_LeftArrow where flags == .command:
                back()
                return true
            default:
                return false
            }
        }
    }
}

// MARK: View

private struct ContextView: View {
    let model: ContextModel
    let panel: ContextActionsPanel
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ContextHeader(context: model.context)
                .padding(.horizontal, 18)
                .frame(height: 66)
            Rectangle().fill(Palette.hairline).frame(height: 1)
            Group {
                switch model.stage {
                case .list: list
                case .prompt(let action): prompt(action)
                case .running(let action): outcome(action, output: nil, error: nil)
                case .result(let action, let output): outcome(action, output: output, error: nil)
                case .failed(let action, let message): outcome(action, output: nil, error: message)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .id(model.stageID)
            .transition(.opacity)
            Rectangle().fill(Palette.hairline).frame(height: 1)
            footer
                .padding(.horizontal, 16)
                .frame(height: 32)
        }
        .onAppear { focused = true }
        .onChange(of: model.stageID) { _, _ in focused = true }
    }

    // MARK: Stages

    private var list: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.tertiary)
                TextField(ContextPanelPhrases.filter.text, text: Binding(get: { model.filter }, set: { model.filter = $0; model.selection = 0 }))
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .focused($focused)
            }
            .padding(.horizontal, 18)
            .frame(height: 40)
            if model.visible.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: model.actions.isEmpty ? "hand.point.up.left" : "magnifyingglass")
                        .font(.system(size: 22, weight: .semibold)).foregroundStyle(Palette.tertiary)
                    Text(model.actions.isEmpty ? ContextPanelPhrases.emptyHint.text : ContextPanelPhrases.noMatch.text)
                        .font(.system(size: 12.5)).foregroundStyle(Palette.secondary).multilineTextAlignment(.center)
                        .frame(maxWidth: 380)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 1) {
                            ForEach(Array(model.visible.enumerated()), id: \.element.id) { index, action in
                                ActionRow(action: action, selected: index == model.selection, number: index < 9 ? index + 1 : nil)
                                    .id(action.id)
                                    .onTapGesture { panel.choose(action) }
                                    .onHover { if $0 { model.selection = index } }
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.bottom, 8)
                    }
                    .onChange(of: model.selection) { _, selection in
                        guard model.visible.indices.contains(selection) else { return }
                        proxy.scrollTo(model.visible[selection].id, anchor: nil)
                    }
                }
            }
        }
    }

    private func prompt(_ action: ActionDefinition) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            ActionTitle(action: action, busy: false)
            TextField(action.prompt?.placeholder.text ?? "", text: Binding(get: { model.input }, set: { model.input = $0 }), axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .lineLimit(1...4)
                .focused($focused)
                .onSubmit { panel.submitPrompt() }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.black.opacity(0.28)))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(action.tint.opacity(0.5), lineWidth: 0.8))
            HStack(spacing: 8) {
                Spacer()
                PillButton(title: ContextPanelPhrases.back.text, symbol: "chevron.left") { panel.back() }
                PillButton(title: ContextPanelPhrases.run.text, symbol: "return", prominent: true) { panel.submitPrompt() }
            }
            Spacer(minLength: 0)
        }
        .padding(18)
    }

    private func outcome(_ action: ActionDefinition, output: ActionOutput?, error: String?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ActionTitle(action: action, busy: output == nil && error == nil)
            if let error {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Palette.warning)
                    Text(error).font(.system(size: 13)).foregroundStyle(Palette.ink).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.warning.opacity(0.1)))
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    Spacer()
                    PillButton(title: ContextPanelPhrases.back.text, symbol: "chevron.left") { panel.back() }
                    if action.permissions.contains(.ai) {
                        PillButton(title: AIPhrases.openSettings.text, symbol: "key.fill", prominent: true) { panel.openAISettings() }
                    }
                }
            } else if case .files(let urls) = output {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(urls, id: \.self) { url in
                            HStack(spacing: 10) {
                                FileThumb(path: url.path, size: 30)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(url.lastPathComponent).font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.ink).lineLimit(1).truncationMode(.middle)
                                    Text(ContextPanelPhrases.size(url)).font(.system(size: 11)).foregroundStyle(Palette.tertiary)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack(spacing: 8) {
                    Spacer()
                    PillButton(title: Phrases.toShelf.text, symbol: "tray.and.arrow.down") { panel.shelveResult() }
                    PillButton(title: Phrases.reveal.text, symbol: "folder", prominent: true) {
                        NSWorkspace.shared.activateFileViewerSelecting(urls)
                        panel.close()
                    }
                }
            } else {
                ScrollView {
                    Text(model.resultText ?? " ")
                        .font(.system(size: 13.5))
                        .foregroundStyle(Palette.ink)
                        .lineSpacing(2.5)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.black.opacity(0.22)))
                HStack(spacing: 8) {
                    PillButton(title: ContextPanelPhrases.back.text, symbol: "chevron.left") { panel.back() }
                    Spacer()
                    if output != nil {
                        PillButton(title: Phrases.toShelf.text, symbol: "tray.and.arrow.down") { panel.shelveResult() }
                        PillButton(title: ContextPanelPhrases.paste.text, symbol: "text.insert") { panel.pasteResult() }
                        PillButton(title: Phrases.copy.text, symbol: "doc.on.doc", prominent: true) { panel.copyResult() }
                    }
                }
            }
        }
        .padding(18)
    }

    // MARK: Footer

    @ViewBuilder private var footer: some View {
        HStack(spacing: 14) {
            switch model.stage {
            case .list:
                hint("↩", ContextPanelPhrases.run.text)
                hint("⌘1–9", ContextPanelPhrases.quick.text)
                hint("esc", ContextPanelPhrases.closeHint.text)
            case .prompt, .running:
                hint("↩", ContextPanelPhrases.run.text)
                hint("esc", ContextPanelPhrases.back.text)
            case .result(_, .text):
                hint("⌘C", Phrases.copy.text)
                hint("⌘↩", ContextPanelPhrases.paste.text)
                hint("⌫", ContextPanelPhrases.back.text)
            case .result, .failed:
                hint("⌫", ContextPanelPhrases.back.text)
                hint("esc", ContextPanelPhrases.closeHint.text)
            }
            Spacer()
            if model.context.fromClipboard {
                Label(ContextPanelPhrases.fromClipboard.text, systemImage: "doc.on.clipboard")
                    .font(.system(size: 10.5, weight: .medium)).foregroundStyle(Palette.tertiary)
            }
        }
    }

    private func hint(_ key: String, _ text: String) -> some View {
        HStack(spacing: 4) {
            Text(key).font(.system(size: 10, weight: .bold, design: .rounded)).foregroundStyle(Palette.ink)
            Text(text).font(.system(size: 10.5)).foregroundStyle(Palette.tertiary)
        }
    }
}

/// What the actions will work on: a thumbnail or icon, its kind and a glimpse of it.
private struct ContextHeader: View {
    let context: ActionContext

    var body: some View {
        HStack(spacing: 12) {
            preview.frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(kindLine).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Palette.ink).lineLimit(1)
                Text(glimpse).font(.system(size: 11.5)).foregroundStyle(Palette.secondary).lineLimit(2).truncationMode(.tail)
            }
            Spacer(minLength: 8)
            KeyCaps(keys: ["⌃", "⌥", "A"], size: 18).opacity(0.7)
        }
    }

    @ViewBuilder private var preview: some View {
        switch context.primary {
        case .image where context.image != nil:
            Image(nsImage: context.image!).resizable().aspectRatio(contentMode: .fill)
                .frame(width: 40, height: 40).clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        case .image, .file, .folder:
            if let first = context.files.first { FileThumb(path: first.path, size: 40) } else { symbol("doc") }
        case .url:
            symbol("link")
        case .text:
            symbol("text.alignleft")
        case .none:
            symbol("hand.point.up.left")
        }
    }

    private func symbol(_ name: String) -> some View {
        Image(systemName: name).font(.system(size: 17, weight: .semibold)).foregroundStyle(Palette.accent)
            .frame(width: 40, height: 40)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Palette.accent.opacity(0.14)))
    }

    private var kindLine: String {
        switch context.primary {
        case .text: ContextPanelPhrases.textKind(Say.number(context.text?.count ?? 0))
        case .url: ContextPanelPhrases.link.text + " · " + (context.url?.host ?? "")
        case .image:
            if let image = context.image { ContextPanelPhrases.image.text + " · \(Int(image.size.width))×\(Int(image.size.height))" }
            else { context.files.count == 1 ? ContextPanelPhrases.image.text : ContextPanelPhrases.images(context.files.count) }
        case .file: context.files.count == 1 ? ContextPanelPhrases.file.text : ContextPanelPhrases.files(context.files.count)
        case .folder: context.files.count == 1 ? ContextPanelPhrases.folder.text : ContextPanelPhrases.files(context.files.count)
        case .none: ContextPanelPhrases.nothing.text
        }
    }

    private var glimpse: String {
        switch context.primary {
        case .text: (context.text ?? "").replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        case .url: context.url?.absoluteString ?? ""
        case .image, .file, .folder: context.files.isEmpty ? (context.fromClipboard ? ContextPanelPhrases.fromClipboard.text : "") : context.files.map(\.lastPathComponent).joined(separator: ", ")
        case .none: ContextPanelPhrases.nothingDetail.text
        }
    }
}

private struct ActionTitle: View {
    let action: ActionDefinition
    let busy: Bool

    var body: some View {
        HStack(spacing: 10) {
            ActionGlyph(action: action, size: 30)
            Text(action.title.text).font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.ink)
            Spacer()
            if busy { Spinner(size: 13, color: action.tint) }
        }
    }
}

private struct ActionGlyph: View {
    let action: ActionDefinition
    var size: CGFloat = 28

    var body: some View {
        Image(systemName: action.symbol).font(.system(size: size * 0.48, weight: .semibold)).foregroundStyle(action.tint)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous).fill(action.tint.opacity(0.15)))
    }
}

private struct ActionRow: View {
    let action: ActionDefinition
    let selected: Bool
    let number: Int?

    var body: some View {
        HStack(spacing: 12) {
            ActionGlyph(action: action)
            Text(action.title.text).font(.system(size: 13.5, weight: .medium)).foregroundStyle(Palette.ink).lineLimit(1)
            if action.permissions.contains(.ai) {
                Text(AIService.shared.ready ? "AI" : ContextPanelPhrases.keyNeeded.text)
                    .font(.system(size: 9, weight: .bold)).foregroundStyle(AIService.shared.ready ? action.tint : Palette.tertiary)
                    .padding(.horizontal, 5).frame(height: 15)
                    .background(Capsule().fill((AIService.shared.ready ? action.tint : Color.white).opacity(0.12)))
            }
            Spacer(minLength: 8)
            if let number, selected {
                Text("⌘\(number)").font(.system(size: 10, weight: .semibold, design: .rounded)).foregroundStyle(Palette.tertiary)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 40)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(selected ? Color.white.opacity(0.12) : Color.clear))
        .contentShape(Rectangle())
    }
}

enum ContextPanelPhrases {
    static let actions = Phrase("Actions…", ru: "Действия…", uk: "Дії…", fr: "Actions…")
    static let filter = Phrase("Find an action", ru: "Найти действие", uk: "Знайти дію", fr: "Trouver une action")
    static let run = Phrase("run", ru: "выполнить", uk: "виконати", fr: "lancer")
    static let quick = Phrase("quick pick", ru: "быстрый выбор", uk: "швидкий вибір", fr: "choix rapide")
    static let closeHint = Phrase("close", ru: "закрыть", uk: "закрити", fr: "fermer")
    static let back = Phrase("Back", ru: "Назад", uk: "Назад", fr: "Retour")
    static let paste = Phrase("Paste", ru: "Вставить", uk: "Вставити", fr: "Coller")
    static let fromClipboard = Phrase("From the clipboard", ru: "Из буфера обмена", uk: "З буфера обміну", fr: "Depuis le presse-papiers")
    static let keyNeeded = Phrase("KEY", ru: "КЛЮЧ", uk: "КЛЮЧ", fr: "CLÉ")
    static let link = Phrase("Link", ru: "Ссылка", uk: "Посилання", fr: "Lien")
    static let image = Phrase("Image", ru: "Картинка", uk: "Зображення", fr: "Image")
    static let file = Phrase("File", ru: "Файл", uk: "Файл", fr: "Fichier")
    static let folder = Phrase("Folder", ru: "Папка", uk: "Тека", fr: "Dossier")
    static let nothing = Phrase("Nothing selected", ru: "Ничего не выделено", uk: "Нічого не виділено", fr: "Rien de sélectionné")
    static let nothingDetail = Phrase("The clipboard is empty too", ru: "Буфер обмена тоже пуст", uk: "Буфер обміну теж порожній", fr: "Le presse-papiers est vide aussi")
    static let emptyHint = Phrase("Select text, a link, an image or files in any app, then press ⌃⌥A.",
                                  ru: "Выделите текст, ссылку, картинку или файлы в любом приложении и нажмите ⌃⌥A.",
                                  uk: "Виділіть текст, посилання, зображення чи файли в будь-якому застосунку й натисніть ⌃⌥A.",
                                  fr: "Sélectionnez du texte, un lien, une image ou des fichiers, puis appuyez sur ⌃⌥A.")
    static let noMatch = Phrase("No action by that name", ru: "Такого действия нет", uk: "Такої дії немає", fr: "Aucune action de ce nom")

    @MainActor static func textKind(_ count: String) -> String {
        Phrase("Text · %@ characters", ru: "Текст · %@ симв.", uk: "Текст · %@ симв.", fr: "Texte · %@ caractères")(count)
    }
    @MainActor static func files(_ count: Int) -> String {
        Phrase("%d items", ru: "Объектов: %d", uk: "Обʼєктів: %d", fr: "%d éléments")(count)
    }
    @MainActor static func images(_ count: Int) -> String {
        Phrase("%d images", ru: "Картинок: %d", uk: "Зображень: %d", fr: "%d images")(count)
    }
    @MainActor static func size(_ url: URL) -> String {
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file) + " · " + url.deletingLastPathComponent().lastPathComponent
    }
}

extension Phrases {
    static let close = Phrase("Close", ru: "Закрыть", uk: "Закрити", fr: "Fermer")
}
