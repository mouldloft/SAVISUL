#if MOULD_ENGINE
import AppKit
import MouldEngine
import Observation
import SwiftUI

/// The assistant's panel, ⌃⌥H: the selection comes along, the answer streams in, every step and every question for
/// consent shows in order.
@MainActor
@Observable
final class MindPanel {
    static let shared = MindPanel()
    @ObservationIgnored private var panel: OverlayPanel?
    @ObservationIgnored private var monitor: Any?
    @ObservationIgnored private var clicks: Any?
    private(set) var isOpen = false
    /// The browser in front when the panel opened, for "This page".
    private(set) var browser: String?
    private static let size = NSSize(width: 580, height: 640)

    func toggle() {
        if isOpen { close() } else { open() }
    }

    func open() {
        guard !isOpen else { return }
        if MindHost.shared.engine == nil { MindHost.shared.start() } else { MindHost.shared.syncLocalModels() }
        browser = BrowserPage.supported(NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
        SelectionReader.read { [weak self] context in self?.open(with: context) }
    }

    func open(with context: ActionContext) {
        let conversation = MindHost.shared.conversation
        if conversation.running == nil {
            conversation.attachments.removeAll()
            conversation.selectedFiles.removeAll()
            // The clipboard standing in for an empty selection isn't brought along: only what the person selected.
            if !context.fromClipboard {
                if let text = context.text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    conversation.attachments.append(Attachment(kind: .text, title: MindPhrases.selectedText.text, text: text))
                }
                if !context.files.isEmpty {
                    conversation.selectedFiles = context.files
                    conversation.attachments.append(Attachment(kind: .file, title: MindPhrases.files(context.files.count),
                                                               text: context.files.map(\.path).joined(separator: "\n")))
                }
            }
        }
        guard !isOpen else { return }
        isOpen = true
        let panel = self.panel ?? make()
        Glass.fadeIn(panel, to: Glass.spotlightFrame(size: Self.size), lift: 10, key: true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            nonisolated(unsafe) let event = event
            let consumed = MainActor.assumeIsolated { MindPanel.shared.key(event) }
            return consumed ? nil : event
        }
        // A click in another app closes it, as Spotlight does; whatever runs keeps running.
        clicks = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { _ in
            MainActor.assumeIsolated { MindPanel.shared.close() }
        }
    }

    func close() {
        guard isOpen else { return }
        isOpen = false
        for watcher in [monitor, clicks] { if let watcher { NSEvent.removeMonitor(watcher) } }
        monitor = nil
        clicks = nil
        if let panel { Glass.fadeOut(panel) }
        // The task goes on; a question it still has moves to the island.
        MindHost.shared.panelClosed()
    }

    private func key(_ event: NSEvent) -> Bool {
        switch Int(event.keyCode) {
        case 53:  // Esc stops a running request first, then closes.
            if MindHost.shared.conversation.running != nil { MindHost.shared.cancel() } else { close() }
            return true
        case 45 where event.modifierFlags.contains(.command):  // ⌘N
            MindHost.shared.conversation.newSession()
            return true
        default:
            return false
        }
    }

    private func make() -> OverlayPanel {
        let panel = OverlayPanel(size: Self.size, key: true, level: .floating)
        panel.contentView = Glass.host(MindView(host: MindHost.shared, conversation: MindHost.shared.conversation, panel: self), size: Self.size, radius: 26)
        self.panel = panel
        return panel
    }

    /// The page in the browser in front, fetched and attached as someone else's text.
    func attachPage() {
        guard let browser else { return }
        Task {
            guard let url = BrowserPage.currentURL(browser) else {
                MindHost.shared.conversation.note(MindPhrases.noPage.text)
                return
            }
            do {
                let text = try await WebPage.text(url)
                MindHost.shared.conversation.attachments.removeAll { $0.kind == .page }
                MindHost.shared.conversation.attachments.append(Attachment(kind: .page, title: url.host ?? url.absoluteString, text: text, url: url))
            } catch {
                MindHost.shared.conversation.note(error.localizedDescription)
            }
        }
    }
}

/// The address of the page in front, read from the browser with its own scripting (the person is asked once).
enum BrowserPage {
    static let chromium = ["com.google.Chrome", "com.microsoft.edgemac", "com.brave.Browser", "company.thebrowser.Browser", "com.vivaldi.Vivaldi",
                           "com.operasoftware.Opera", "ru.yandex.desktop.yandex-browser"]

    static func supported(_ bundleID: String?) -> String? {
        guard let bundleID, bundleID == "com.apple.Safari" || chromium.contains(bundleID) else { return nil }
        return bundleID
    }

    @MainActor static func currentURL(_ bundleID: String) -> URL? {
        let source = bundleID == "com.apple.Safari"
            ? "tell application id \"com.apple.Safari\" to return URL of front document"
            : "tell application id \"\(bundleID)\" to return URL of active tab of front window"
        var error: NSDictionary?
        guard let text = NSAppleScript(source: source)?.executeAndReturnError(&error).stringValue, error == nil,
              let url = URL(string: text), url.scheme == "https" || url.scheme == "http" else { return nil }
        return url
    }
}

/// Panel renders (--dump-panels): the assistant on sample conversations. No engine runs and nothing of the person's is read.
@MainActor
enum MindRender {
    static func dump(to folder: URL, completion: @escaping () -> Void) {
        let host = MindHost.shared
        host.preview(models: [LocalModel(id: LocalModels.recommendedID, title: LocalModels.recommended.title, file: URL(fileURLWithPath: "/dev/null"),
                                         memoryGB: 3.6, quality: 0.72).profile])
        let panel = NSSize(width: 580, height: 640), card = NSSize(width: 400, height: 820)
        let background = RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Color(red: 0.11, green: 0.105, blue: 0.1))
        func chat(_ conversation: MindConversation) -> AnyView {
            AnyView(MindView(host: host, conversation: conversation, panel: MindPanel.shared).frame(width: panel.width, height: panel.height).background(background))
        }
        let shots: [(name: String, size: NSSize, view: AnyView)] = [
            ("assistant", panel, chat(empty())), ("assistant-health", panel, chat(health())), ("assistant-consent", panel, chat(consent())),
            ("assistant-photos", panel, chat(photos())),
            ("assistant-settings", card, AnyView(MindCard(suite: Suite.shared).padding(14).frame(width: card.width, height: card.height, alignment: .top).background(background)))
        ]
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -4000, y: -4000), size: panel), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.orderFrontRegardless()

        func shoot(_ index: Int) {
            guard index < shots.count else {
                window.orderOut(nil)
                completion()
                return
            }
            window.setContentSize(shots[index].size)
            window.contentView = NSHostingView(rootView: shots[index].view.environment(\.colorScheme, .dark))
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                MainActor.assumeIsolated {
                    if let content = window.contentView {
                        content.layoutSubtreeIfNeeded()
                        if let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
                            content.cacheDisplay(in: content.bounds, to: bitmap)
                            try? bitmap.representation(using: .png, properties: [:])?.write(to: folder.appendingPathComponent("panels-\(shots[index].name).png"))
                        }
                    }
                    shoot(index + 1)
                }
            }
        }
        shoot(0)
    }

    private static let sortPrompt = Phrase("Sort my Downloads into folders", ru: "Разложи Загрузки по папкам", uk: "Розклади Завантаження по теках",
                                           fr: "Range mes Téléchargements dans des dossiers")
    private static let sortAnswer = Phrase("I'll sort Downloads by kind. Here's what will move:", ru: "Разложу Загрузки по типам. Вот что переместится:",
                                           uk: "Розкладу Завантаження за типами. Ось що переміститься:", fr: "Je range les Téléchargements par type. Voici ce qui va bouger :")
    private static let sample = "SAVISUL turns the notch into a living island: music, timers, files and AI agents, with one shortcut for everything you select."

    private static func empty() -> MindConversation {
        let conversation = MindConversation()
        conversation.attachments = [Attachment(kind: .text, title: MindPhrases.selectedText.text, text: sample)]
        return conversation
    }

    private static func health() -> MindConversation {
        let conversation = MindConversation()
        conversation.begin(MindRequest(MindPhrases.checkMac.text, taskID: "render-health"))
        let call = ToolCall(id: "render-health-call", tool: "mac.health")
        conversation.apply(.toolStarted(call, title: "Mac health check"))
        conversation.apply(.toolFinished(call, summary: "The CPU is busy."))
        let output = ToolOutput([
            "resources": ["memoryTotalGB": 16, "memoryAvailableGB": 5.2, "cpuLoadPercent": 81, "thermal": "fair", "onBattery": true, "batteryPercent": 64],
            "diskFreeGB": 212, "diskTotalGB": 494,
            "topMemory": [["name": "Safari", "memoryMB": 3120], ["name": "Figma", "memoryMB": 1840], ["name": "Xcode", "memoryMB": 1610]],
            "topCPU": [["name": "Xcode", "cpuPercent": 214]]
        ])
        conversation.apply(.finished(answer: MindReport.describe("mac.health", output)))
        conversation.end()
        return conversation
    }

    /// A photo search, with macOS's own pictures standing in for the person's.
    private static func photos() -> MindConversation {
        let conversation = MindConversation()
        conversation.begin(MindRequest(Phrase("Find photos of birds", ru: "Найди фото птиц", uk: "Знайди фото птахів", fr: "Trouve des photos d’oiseaux").text,
                                       taskID: "render-photos"))
        let understand = ToolCall(id: "render-photos-understand", tool: "photos.understand")
        conversation.apply(.toolStarted(understand, title: PhotoPhrases.understanding.text))
        conversation.apply(.toolFinished(understand, summary: "bird"))
        let call = ToolCall(id: "render-photos-call", tool: "photos.find")
        conversation.apply(.toolStarted(call, title: "Find photos"))
        let samples = ["Eagle", "Owl", "Parrot", "Penguin"].map { URL(fileURLWithPath: "/Library/User Pictures/Animals/\($0).heic").resolvingSymlinksInPath() }
        conversation.found(samples.map { PhotoHit(PhotoRecord(source: .file, location: $0.path, name: $0.lastPathComponent, taken: nil, changed: .now, labels: [:])) })
        conversation.apply(.toolFinished(call, summary: "Found 4 pictures"))
        conversation.apply(.finished(answer: PhotoPhrases.found(samples.count)))
        conversation.end()
        return conversation
    }

    private static func consent() -> MindConversation {
        let conversation = MindConversation()
        conversation.begin(MindRequest(sortPrompt.text, taskID: "render-sort"))
        conversation.apply(.routed(model: "local:" + LocalModels.recommendedID, title: LocalModels.recommended.title, local: true,
                                   reasons: ["personal data stays on this Mac"]))
        conversation.apply(.text(sortAnswer.text))
        let folders = MindPhrases.folderNames
        let files = [("IMG_2041.HEIC", "Images"), ("invoice-0921.pdf", "Documents"), ("budget-q4.xlsx", "Spreadsheets"), ("keynote.key", "Presentations"),
                     ("SAVISUL-2.3.dmg", "Archives"), ("voice-memo.m4a", "Audio")]
        let changes = files.map { file, kind in
            Change(.move, "/Downloads/\(file)", "/Downloads/\(folders[kind]?.string ?? kind)/\(file)")
        }
        let preview = ToolPreview(summary: "Sort 24 items into 6 folders", changes: changes, omitted: 18)
        conversation.confirm(ConfirmationRequest(id: "render-consent", taskID: "render-sort", title: "Sort a folder",
                                                 items: [.init(tool: "files.sort_folder", toolTitle: "Sort a folder", risk: .reversible, preview: preview)],
                                                 tainted: false))
        return conversation
    }
}

// MARK: Views

private struct MindView: View {
    let host: MindHost
    let conversation: MindConversation
    let panel: MindPanel
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header.padding(.horizontal, 18).frame(height: 58)
            Rectangle().fill(Palette.hairline).frame(height: 1)
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
            Rectangle().fill(Palette.hairline).frame(height: 1)
            composer.padding(.horizontal, 14).padding(.vertical, 10)
        }
        .onAppear { focused = true }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles").font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text(MindPhrases.title.text).font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.ink)
                if let route = conversation.route {
                    Label(route.title, systemImage: route.local ? "lock.fill" : "cloud.fill")
                        .font(.system(size: 11)).foregroundStyle(Palette.secondary).lineLimit(1)
                        .help(route.reasons.joined(separator: " · "))
                } else {
                    Text(statusLine).font(.system(size: 11)).foregroundStyle(Palette.secondary).lineLimit(1)
                }
            }
            Spacer()
            Button { host.undoLast() } label: { Image(systemName: "arrow.uturn.backward") }
                .buttonStyle(.plain).foregroundStyle(Palette.secondary).help(MindPhrases.undoLast.text)
            Button { conversation.newSession() } label: { Image(systemName: "square.and.pencil") }
                .buttonStyle(.plain).foregroundStyle(Palette.secondary).help(MindPhrases.newChat.text)
                .disabled(conversation.running != nil)
        }
        .font(.system(size: 13, weight: .semibold))
    }

    private var statusLine: String {
        switch host.phase {
        case .off, .starting: MindPhrases.starting.text
        case .failed(let message): message
        case .ready:
            if let chosen = MindHost.choose(host.models, mode: host.mode, personal: false, personalToCloud: host.personalToCloud),
               let profile = host.models.first(where: { $0.id == chosen }) {
                (profile.locality == .local ? MindPhrases.onThisMac.text : MindPhrases.cloud.text) + " · " + profile.title
            } else if let local = host.models.first(where: { $0.locality == .local }) { MindPhrases.onThisMac.text + " · " + local.title }
            else if let cloud = host.models.first { MindPhrases.cloud.text + " · " + cloud.title }
            else { MindPhrases.noModel.text }
        }
    }

    @ViewBuilder private var content: some View {
        if conversation.isEmpty {
            EmptyMind(host: host, conversation: conversation, panel: panel)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(conversation.items) { item in
                            MindItemView(item: item, host: host).id(item.id)
                        }
                    }
                    .padding(16)
                }
                .onChange(of: conversation.items.last?.text) { _, _ in
                    if let last = conversation.items.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
                .onChange(of: conversation.items.count) { _, _ in
                    if let last = conversation.items.last { withAnimation(.quickSpring) { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
            }
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !conversation.attachments.isEmpty || panel.browser != nil {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(conversation.attachments.enumerated()), id: \.offset) { index, attachment in
                            Chip(symbol: symbol(attachment.kind), text: attachment.title) {
                                conversation.attachments.remove(at: index)
                                if attachment.kind == .file { conversation.selectedFiles.removeAll() }
                            }
                        }
                        if panel.browser != nil && !conversation.attachments.contains(where: { $0.kind == .page }) {
                            Button { panel.attachPage() } label: {
                                Label(MindPhrases.thisPage.text, systemImage: "plus").font(.system(size: 11.5, weight: .medium))
                                    .padding(.horizontal, 10).frame(height: 24)
                                    .background(Capsule().strokeBorder(Palette.hairline.opacity(3), lineWidth: 1))
                            }
                            .buttonStyle(.plain).foregroundStyle(Palette.secondary)
                        }
                    }
                }
            }
            HStack(alignment: .bottom, spacing: 10) {
                TextField(MindPhrases.placeholder.text, text: Binding(get: { conversation.input }, set: { conversation.input = $0 }), axis: .vertical)
                    .textFieldStyle(.plain).font(.system(size: 14)).lineLimit(1...5).focused($focused)
                    .onSubmit(send)
                    .disabled(host.phase != .ready)
                if conversation.running != nil {
                    Button { host.cancel() } label: { Image(systemName: "stop.circle.fill").font(.system(size: 22)) }
                        .buttonStyle(.plain).foregroundStyle(Palette.secondary).help(MindPhrases.stop.text)
                } else {
                    Button(action: send) { Image(systemName: "arrow.up.circle.fill").font(.system(size: 22)) }
                        .buttonStyle(.plain).foregroundStyle(conversation.input.isEmpty ? Palette.tertiary : Palette.accent)
                        .disabled(conversation.input.trimmingCharacters(in: .whitespaces).isEmpty || host.phase != .ready)
                }
            }
        }
    }

    private func send() {
        let text = conversation.input
        conversation.input = ""
        host.ask(text)
    }

    private func symbol(_ kind: Attachment.Kind) -> String {
        switch kind {
        case .text: "text.quote"
        case .file: "doc.on.doc"
        case .page: "globe"
        case .clipboard: "clipboard"
        case .image: "photo"
        }
    }
}

private struct EmptyMind: View {
    let host: MindHost
    let conversation: MindConversation
    let panel: MindPanel

    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "sparkles").font(.system(size: 30, weight: .semibold)).foregroundStyle(Palette.accent)
            Text(MindPhrases.hello.text).font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.ink)
            Text(MindPhrases.helloDetail.text).font(.system(size: 12.5)).foregroundStyle(Palette.secondary)
                .multilineTextAlignment(.center).frame(maxWidth: 400)
            if host.phase == .ready && host.models.isEmpty {
                ModelSetup(host: host)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                Quick(symbol: "stethoscope", title: MindPhrases.checkMac.text) {
                    host.perform("mac.health", [:], title: MindPhrases.checkMac.text)
                }
                Quick(symbol: "photo.on.rectangle.angled", title: PhotoPhrases.quick.text) { conversation.input = PhotoPhrases.prompt.text }
                Quick(symbol: "folder.badge.gearshape", title: MindPhrases.sortDownloads.text) {
                    host.perform("files.sort_folder", ["folder": "~/Downloads", "by": "type", "names": MindPhrases.folderNames],
                                 title: MindPhrases.sortDownloads.text, quietWhenEmpty: true)
                }
                if conversation.attachments.contains(where: { $0.kind == .text || $0.kind == .page }) {
                    Quick(symbol: "text.append", title: MindPhrases.summarize.text) { host.ask(MindPhrases.summarizePrompt.text, mode: .answer) }
                }
                Quick(symbol: "arrow.uturn.backward", title: MindPhrases.undo.text) { host.undoLast() }
            }
            .frame(maxWidth: 420)
            .disabled(host.phase != .ready)
            Spacer()
        }
        .padding(20)
    }
}

private struct ModelSetup: View {
    let host: MindHost

    var body: some View {
        VStack(spacing: 6) {
            Text(MindPhrases.noModel.text).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Palette.warning)
            Text(LocalModels.serverInstalled ? MindPhrases.noModelDetail.text : MindPhrases.installLlama.text)
                .font(.system(size: 11.5)).foregroundStyle(Palette.secondary).multilineTextAlignment(.center).frame(maxWidth: 400)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.05)))
    }
}

private struct Quick: View {
    let symbol: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.accent).frame(width: 18)
                Text(title).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Palette.ink).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12).frame(height: 38)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06)))
        }
        .buttonStyle(PressableStyle())
    }
}

private struct Chip: View {
    let symbol: String
    let text: String
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 10.5, weight: .semibold))
            Text(text).font(.system(size: 11.5, weight: .medium)).lineLimit(1)
            Button(action: remove) { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)) }.buttonStyle(.plain)
        }
        .foregroundStyle(Palette.ink)
        .padding(.horizontal, 10).frame(height: 24)
        .background(Capsule().fill(Palette.accent.opacity(0.16)))
    }
}

private struct MindItemView: View {
    let item: MindConversation.Item
    let host: MindHost

    var body: some View {
        switch item.kind {
        case .request:
            HStack {
                Spacer(minLength: 60)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(item.text).font(.system(size: 13.5)).foregroundStyle(Palette.ink).textSelection(.enabled)
                    if let detail = item.detail { Text(detail).font(.system(size: 10.5)).foregroundStyle(Palette.tertiary) }
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.accent.opacity(0.16)))
            }
        case .answer:
            Text(Self.markdown(item.text)).font(.system(size: 13.5)).foregroundStyle(Palette.ink).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .step:
            HStack(alignment: .top, spacing: 8) {
                status.frame(width: 16, height: 16)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.text).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Palette.ink)
                    if let detail = item.detail { Text(detail).font(.system(size: 11.5)).foregroundStyle(Palette.secondary).lineLimit(3) }
                }
            }
        case .plan:
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    status.frame(width: 16, height: 16)
                    Text(item.text).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Palette.ink)
                }
                ForEach(Array(item.steps.enumerated()), id: \.offset) { index, step in
                    Text("\(index + 1). \(step)").font(.system(size: 12)).foregroundStyle(Palette.secondary)
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.05)))
        case .consent:
            ConsentCard(item: item, host: host)
        case .note:
            Text(item.text).font(.system(size: 12)).foregroundStyle(Palette.secondary)
        case .failure:
            Label(item.text, systemImage: "exclamationmark.triangle.fill").font(.system(size: 12)).foregroundStyle(Palette.warning)
        case .photos:
            PhotoGrid(photos: item.photos)
        }
    }

    @ViewBuilder private var status: some View {
        switch item.status {
        case .running: ProgressView().controlSize(.small).scaleEffect(0.7)
        case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.positive)
        case .failed: Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.danger)
        case .declined: Image(systemName: "hand.raised.fill").foregroundStyle(Palette.tertiary)
        }
    }

    static func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }
}

private struct ConsentCard: View {
    let item: MindConversation.Item
    let host: MindHost
    private static let listed = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "hand.raised.fill").foregroundStyle(Palette.accent)
                Text(item.text).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Palette.ink)
            }
            if item.request?.tainted == true {
                Label(MindPhrases.tainted.text, systemImage: "exclamationmark.shield.fill").font(.system(size: 11)).foregroundStyle(Palette.warning)
            }
            ForEach(Array((item.request?.items ?? []).enumerated()), id: \.offset) { _, entry in
                let preview = entry.preview
                let shown = preview.changes.prefix(Self.listed)
                VStack(alignment: .leading, spacing: 3) {
                    if (item.request?.items.count ?? 0) > 1 {
                        Text(MindPhrases.tool(entry.tool, entry.toolTitle)).font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.ink)
                    }
                    // Tools describe themselves in English; the list of changes is said in the person's language.
                    if preview.changes.isEmpty || Suite.shared.language == .en {
                        Text(preview.summary).font(.system(size: 12)).foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(Array(shown.enumerated()), id: \.offset) { _, change in
                        Text("· " + MindPhrases.change(change)).font(.system(size: 11)).foregroundStyle(Palette.secondary).lineLimit(1).truncationMode(.middle)
                    }
                    let rest = preview.changes.count - shown.count + preview.omitted
                    if rest > 0 {
                        Text(MindPhrases.andMore(rest)).font(.system(size: 11)).foregroundStyle(Palette.tertiary)
                    }
                    ForEach(preview.warnings, id: \.self) { warning in
                        Label(warning, systemImage: "exclamationmark.triangle.fill").font(.system(size: 11)).foregroundStyle(Palette.warning)
                    }
                }
            }
            if item.status == .running {
                HStack(spacing: 8) {
                    Spacer()
                    PillButton(title: MindPhrases.deny.text) { host.decide(item.id, .declined) }
                    PillButton(title: MindPhrases.allow.text, prominent: true) { host.decide(item.id, .approved) }
                        .keyboardShortcut(.return, modifiers: .command)
                }
            } else {
                Text(item.detail ?? (item.status == .done ? MindPhrases.allowed.text : MindPhrases.denied.text))
                    .font(.system(size: 11)).foregroundStyle(Palette.tertiary)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.accent.opacity(item.status == .running ? 0.7 : 0.2), lineWidth: 1))
    }
}
#endif
