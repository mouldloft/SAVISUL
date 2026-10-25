#if MOULD_ENGINE
import AppKit
import CryptoKit
import MouldEngine
import Observation
import SwiftUI

/// SAVISUL's assistant, running on Mould Engine. The engine is a separate, proprietary product; this is SAVISUL's side:
/// it builds the engine with SAVISUL's storage, AI settings, local models and tools, asks the person through the
/// assistant panel or the island, and shows the engine's work around the notch, with the panda when it's on.
@MainActor
@Observable
final class MindHost {
    static let shared = MindHost()

    enum Phase: Equatable {
        case off, starting, ready
        case failed(String)
    }

    private(set) var phase: Phase = .off
    @ObservationIgnored private(set) var engine: MouldEngine?
    let conversation = MindConversation()
    private(set) var models: [ModelProfile] = []
    private(set) var loadedModels: Set<String> = []
    private(set) var memories = 0
    /// 0…1 while the recommended local model downloads.
    private(set) var downloading: Double?
    private(set) var downloadProblem: String?

    var mode: RouterPolicy.Mode {
        didSet { defaults.set(mode.rawValue, forKey: "mind.mode"); applyMind() }
    }
    var personalToCloud: Bool {
        didSet { defaults.set(personalToCloud, forKey: "mind.personalToCloud"); applyMind() }
    }
    /// Folders the assistant may work in, besides what the person selects for one request.
    private(set) var folders: [URL]

    private var defaults: UserDefaults { SettingsDefaults.store }
    @ObservationIgnored private let selection = ManualContextSource(name: "savisul.selection")
    @ObservationIgnored private var listener: Task<Void, Never>?
    @ObservationIgnored private var waiting: [String: CheckedContinuation<ConfirmationDecision, Never>] = [:]
    @ObservationIgnored private var current: Task<Void, Never>?
    @ObservationIgnored private var aiReload: Task<Void, Never>?
    /// One watch on the AI settings at a time, however often the engine restarts.
    @ObservationIgnored private var watchingAI = false
    @ObservationIgnored private var download: ModelDownload?
    /// The island's activity for the task running now.
    @ObservationIgnored private var activity: LiveActivity?
    /// Every tool the engine has, so a request to the model can leave out the ones it doesn't need.
    @ObservationIgnored private var toolNames: Set<String> = []

    private init() {
        let store = SettingsDefaults.store
        mode = RouterPolicy.Mode(rawValue: store.string(forKey: "mind.mode") ?? "") ?? .localFirst
        personalToCloud = store.bool(forKey: "mind.personalToCloud")
        let home = FileManager.default.homeDirectoryForCurrentUser
        let saved = store.stringArray(forKey: "mind.folders")
        folders = (saved ?? [home.appendingPathComponent("Downloads").path, home.appendingPathComponent("Desktop").path]).map { URL(fileURLWithPath: $0) }
    }

    nonisolated static var storage: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("SAVISUL/Mould")
    }

    nonisolated static var modelsFolder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("SAVISUL/Models")
    }

    // MARK: Starting and stopping

    func start() {
        // Only the running app has an engine: panel renders and tests never open the assistant's storage.
        guard engine == nil, phase != .starting, Suite.shared.app?.preview == false else { return }
        phase = .starting
        Task {
            do {
                var configuration = EngineConfiguration(storage: Self.storage)
                configuration.mind = mindConfiguration()
                configuration.localModels = LocalModels.installed()
                let engine = try await MouldEngine(configuration: configuration, broker: MindBroker())
                try await engine.registry.register(MindTools.all(suite: Suite.shared))
                await engine.addSource(selection)
                await engine.addSource(SuiteContextSource())
                if let cloud = CloudModels.backend() { await engine.addBackend(cloud) }
                for folder in folders { engine.grant(folder, writable: true) }
                // Turned off while it was starting: it goes again straight away.
                guard phase == .starting else {
                    await engine.shutdown()
                    return
                }
                self.engine = engine
                toolNames = Set(await engine.registry.names.map(\.rawValue))
                phase = .ready
                listen(engine.pulse)
                watchAI()
                await refresh()
            } catch {
                phase = .failed(MindPhrases.error(error.mould))
            }
        }
    }

    func stop() {
        guard phase != .off else { return }
        phase = .off
        listener?.cancel()
        listener = nil
        current?.cancel()
        for id in Array(waiting.keys) { decide(id, .declined) }
        guard let engine else { return }
        self.engine = nil
        Task { await engine.shutdown() }
    }

    /// The AI settings changed: the engine gets the cloud model they describe now.
    func reloadCloud() {
        guard let engine else { return }
        Task {
            for provider in AIService.Provider.allCases { await engine.mind.removeBackend(provider.rawValue) }
            if let cloud = CloudModels.backend() { await engine.addBackend(cloud) }
            await refresh()
        }
    }

    /// A model was downloaded or removed, or llama.cpp was installed.
    func reloadLocal() {
        guard let engine else { return }
        Task {
            let running = await engine.setLocalModels(LocalModels.installed())
            // llama.cpp arrived after the engine started: only a fresh engine finds it.
            if !running, LocalModels.serverInstalled, conversation.running == nil {
                stop()
                start()
                return
            }
            await refresh()
        }
    }

    /// Panel renders (--dump-panels): looks ready with these models; no engine runs.
    func preview(models: [ModelProfile]) {
        guard Suite.shared.app == nil else { return }
        phase = .ready
        self.models = models
    }

    /// Models dropped into the folder or removed from it, or llama.cpp installed since the engine started: the engine
    /// catches up. Cheap enough to call whenever the assistant or its settings open.
    func syncLocalModels() {
        guard let engine, conversation.running == nil else { return }
        let onDisk = LocalModels.installed()
        if engine.localRuntime == nil {
            if LocalModels.serverInstalled && !onDisk.isEmpty {
                stop()
                start()
            }
            return
        }
        let known = Set(models.filter { $0.backend == "local" }.map(\.id))
        if Set(onDisk.map(\.profile.id)) != known { reloadLocal() }
    }

    func refresh() async {
        guard let engine else { return }
        let status = await engine.status()
        models = status.models
        loadedModels = status.loadedModels
        memories = status.memories
    }

    private func mindConfiguration() -> MindConfiguration {
        var configuration = MindConfiguration()
        configuration.persona = "SAVISUL, the assistant built into this Mac's menu bar app"
        configuration.language = AIService.languageName
        configuration.router = RouterPolicy(mode: mode, allowPersonalToCloud: personalToCloud)
        // What a small model gets wrong without being told: how long to be, to call a tool rather than write about it,
        // and where the person's folders really are.
        let home = FileManager.default.homeDirectoryForCurrentUser
        let folder = { (name: String) in home.appendingPathComponent(name).path }
        configuration.instructions = [
            "Answer briefly: a few sentences or a short list, unless the person asks for more.",
            "When a tool is needed, call it; never write that you are going to call one.",
            "The person's folders: Downloads is \(folder("Downloads")), Desktop is \(folder("Desktop")), Documents is \(folder("Documents")), Pictures is \(folder("Pictures")). Use these exact paths; never make up others."
        ]
        return configuration
    }

    private func applyMind() {
        guard let engine else { return }
        let configuration = mindConfiguration()
        Task { await engine.setMind(configuration) }
    }

    /// The app's language changed: answers follow it.
    func languageChanged() {
        applyMind()
    }

    /// Follows Settings → AI, with a short pause so typing a model name doesn't rebuild the backend on every key.
    private func watchAI() {
        guard !watchingAI else { return }
        watchingAI = true
        withObservationTracking {
            let ai = AIService.shared
            _ = (ai.provider, ai.model, ai.baseURL, ai.hasKey)
        } onChange: {
            Task { @MainActor in MindHost.shared.aiChanged() }
        }
    }

    private func aiChanged() {
        watchingAI = false
        aiReload?.cancel()
        aiReload = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            reloadCloud()
        }
        if engine != nil { watchAI() }
    }

    // MARK: Folders

    func addFolder(_ url: URL) {
        guard !folders.contains(url) else { return }
        folders.append(url)
        defaults.set(folders.map(\.path), forKey: "mind.folders")
        engine?.grant(url, writable: true)
    }

    func removeFolder(_ url: URL) {
        folders.removeAll { $0 == url }
        defaults.set(folders.map(\.path), forKey: "mind.folders")
        engine?.access.revoke(url)
    }

    // MARK: Asking

    func ask(_ prompt: String, mode requestMode: MindRequest.Mode = .assist) {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let engine, !text.isEmpty, conversation.running == nil else { return }
        // A plain everyday request SAVISUL runs itself; what the person brought along goes to the model with it.
        var wanted: Set<String>?
        if requestMode == .assist, conversation.attachments.isEmpty {
            switch MindIntents.route(text) {
            case .photos:
                findPhotos(text)
                return
            case .tool(let tool, let arguments):
                perform(tool, arguments, title: text, quietWhenEmpty: tool == "files.sort_folder")
                return
            case .answer(let answer):
                say(text, answer)
                return
            case .model(let tools):
                wanted = tools
            }
        }
        // The model gets only the tools the words point to; with none, it just answers.
        let mode: MindRequest.Mode = wanted?.isEmpty == true ? .answer : requestMode
        let tools = wanted.map { ToolFilter(excluded: Set(toolNames.subtracting($0).map(ToolName.init(rawValue:)))) } ?? ToolFilter()
        // The person's own AI when they connected one, else the recommended local model; the router chooses only when
        // neither is there or the one chosen can't answer right now.
        let preferred = Self.choose(models, mode: self.mode, personal: !conversation.attachments.isEmpty, personalToCloud: personalToCloud)
        let request = MindRequest(text, mode: mode, attachments: conversation.attachments, session: conversation.session, tools: tools, interactive: true,
                                  model: preferred, instructions: MindIntents.instructions(for: PhotoWords.tokens(text)))
        // Files the person selected may be worked on for this request only.
        for url in conversation.selectedFiles { engine.grant(url, writable: true, taskID: request.taskID) }
        conversation.begin(request)
        let activity = Suite.shared.live.start(symbol: "sparkles", tint: Palette.accent, title: String(text.prefix(40)), detail: MindPhrases.thinking.text)
        self.activity = activity
        let selection = self.selection
        let conversation = self.conversation
        let deltas = conversation.contextDeltas
        current = Task {
            await selection.push(deltas)
            var failure: MouldError?
            var request = request
            for attempt in 0..<2 {
                failure = nil
                do {
                    for try await event in await engine.ask(request) {
                        conversation.apply(event)
                        if case .toolStarted(let call, let title) = event { activity.update(progress: nil, detail: MindPhrases.tool(call.tool, title)) }
                    }
                } catch {
                    failure = error.mould
                    // The chosen model couldn't answer (no internet, a key that stopped working, too big for the memory
                    // free right now): once more, and the router picks one that can.
                    if attempt == 0, request.model != nil, Self.worthAnotherModel(error.mould) {
                        request.model = nil
                        conversation.note(MindPhrases.fellBack.text)
                        continue
                    }
                    conversation.fail(error.mould)
                }
                break
            }
            self.settle(request.taskID)
            conversation.end()
            self.report(activity, failure: failure)
            await self.refresh()
        }
    }

    /// Runs one tool straight from a button, with no model involved. Anything that changes something is still shown
    /// first, with what exactly it will change; `quietWhenEmpty` skips the question when there is nothing to change.
    func perform(_ tool: ToolName, _ arguments: JSONValue, title: String, quietWhenEmpty: Bool = false) {
        guard let engine, conversation.running == nil else { return }
        let taskID = UUID().uuidString
        conversation.begin(MindRequest(title, mode: .assist, taskID: taskID))
        let activity = Suite.shared.live.start(symbol: "sparkles", tint: Palette.accent, title: title)
        self.activity = activity
        let conversation = self.conversation
        current = Task {
            let call = ToolCall(tool: tool, arguments: arguments)
            var origin = Origin(agent: .person, taskID: taskID)
            var started = false
            var failure: MouldError?
            do {
                if let spec = await engine.registry.tool(tool)?.spec, !spec.readOnly {
                    // Admission first, so a folder that isn't granted is said plainly instead of an empty preview.
                    let preview = try await engine.runtime.preview(call, origin: origin)
                    if !(quietWhenEmpty && preview.changes.isEmpty && preview.omitted == 0) {
                        origin.approval = try await engine.runtime.approve(plan: [call], title: title, origin: origin)
                    }
                }
                started = true
                conversation.apply(.toolStarted(call, title: title))
                let output = try await engine.runtime.execute(call, origin: origin)
                conversation.apply(.toolFinished(call, summary: output.summary))
                conversation.apply(.finished(answer: MindReport.describe(tool, output)))
            } catch {
                failure = error.mould
                if started { conversation.apply(.toolFailed(call, error: error.mould)) } else { conversation.fail(error.mould) }
            }
            await engine.runtime.finish(taskID: taskID)
            self.settle(taskID)
            conversation.end()
            self.report(activity, failure: failure)
        }
    }

    /// The model a request goes to: the person's own AI when they connected one and didn't keep the assistant to this Mac
    /// (what they selected goes to a cloud model only if they allowed it); otherwise the recommended local model when it's
    /// here. Nil leaves the choice to the router.
    nonisolated static func choose(_ models: [ModelProfile], mode: RouterPolicy.Mode, personal: Bool, personalToCloud: Bool) -> String? {
        if mode != .localOnly, let own = models.first(where: { $0.backend != "local" }), own.locality == .local || !personal || personalToCloud {
            return own.id
        }
        return models.first { $0.id == "local:" + LocalModels.recommendedID }?.id
    }

    nonisolated static func worthAnotherModel(_ error: MouldError) -> Bool {
        switch error {
        case .unavailable, .backend, .timeout: true
        default: false
        }
    }

    /// An answer SAVISUL knows itself, shown at once.
    private func say(_ prompt: String, _ answer: String) {
        conversation.begin(MindRequest(prompt, mode: .answer))
        conversation.apply(.finished(answer: answer))
        conversation.end()
    }

    /// "Find the photo of…": the model on this Mac only reads the description, then the search runs straight away, so it
    /// works the same with the smallest model, and with none.
    func findPhotos(_ prompt: String) {
        guard let engine, conversation.running == nil else { return }
        let taskID = UUID().uuidString
        conversation.begin(MindRequest(prompt, mode: .assist, taskID: taskID))
        let activity = Suite.shared.live.start(symbol: "photo.on.rectangle.angled", tint: Palette.accent, title: String(prompt.prefix(40)),
                                               detail: PhotoPhrases.understanding.text)
        self.activity = activity
        let conversation = self.conversation
        current = Task {
            let understand = ToolCall(tool: "photos.understand")
            conversation.apply(.toolStarted(understand, title: PhotoPhrases.understanding.text))
            // Asked for a photo before ever allowing Photos: macOS asks now, while it's wanted.
            await PhotoSearch.shared.askForLibraryIfUndecided()
            let terms = await PhotoTerms.read(prompt, engine: engine, model: Self.choose(self.models, mode: self.mode, personal: false,
                                                                                         personalToCloud: self.personalToCloud))
            conversation.apply(.toolFinished(understand, summary: terms.map { $0.scene.isEmpty ? $0.keywords.joined(separator: ", ") : $0.scene } ?? ""))
            var query = PhotoQuery()
            query.words = prompt
            query.scene = terms?.scene ?? ""
            query.keywords = terms?.keywords ?? []
            query.text = terms?.text ?? ""
            var arguments: [String: JSONValue] = ["query": .string(prompt), "keywords": .array(query.keywords.map(JSONValue.string))]
            if !query.scene.isEmpty { arguments["scene"] = .string(query.scene) }
            if !query.text.isEmpty { arguments["text"] = .string(query.text) }
            let call = ToolCall(tool: "photos.find", arguments: .object(arguments))
            var failure: MouldError?
            do {
                conversation.apply(.toolStarted(call, title: MindPhrases.tool("photos.find", "Find photos")))
                let output = try await engine.runtime.execute(call, origin: Origin(agent: .person, taskID: taskID))
                conversation.apply(.toolFinished(call, summary: output.summary))
                let found = output.value["found"]?.int ?? 0, pending = output.value["stillToIndex"]?.int ?? 0
                let sure = output.value["sure"]?.bool ?? (found > 0)
                // Nothing found for a description it couldn't read at all: it asks for one instead.
                let plan = PhotoWords.plan(query, now: .now)
                let understood = !plan.isEmpty || plan.after != nil || plan.before != nil || !query.scene.isEmpty
                let searchesLibrary = PhotoSearch.shared.library && PhotoSearch.shared.access == .authorized
                var answer = found > 0 ? (sure ? PhotoPhrases.found(found) : PhotoPhrases.maybe(found))
                    : !understood ? PhotoPhrases.describe.text
                    : searchesLibrary ? PhotoPhrases.nothing.text : PhotoPhrases.nothingWithoutLibrary.text
                if pending > 0 { answer += "\n" + PhotoPhrases.stillLooking(pending) }
                // Without the meaning the search only has Vision's labels: it says where the better one is.
                if PhotoSearch.shared.model == .missing { answer += "\n" + PhotoPhrases.modelOffer.text }
                conversation.apply(.finished(answer: answer))
            } catch {
                failure = error.mould
                conversation.apply(.toolFailed(call, error: error.mould))
            }
            await engine.runtime.finish(taskID: taskID)
            self.settle(taskID)
            conversation.end()
            self.report(activity, failure: failure)
        }
    }

    func cancel() {
        guard let task = conversation.running else { return }
        current?.cancel()
        settle(task)
        Task { await engine?.cancel(task) }
    }

    func undoLast() {
        guard let engine, conversation.running == nil else { return }
        Task {
            do {
                let undone = try await engine.undoLast()
                conversation.note(MindPhrases.undone(undone))
            } catch {
                conversation.fail(error.mould)
            }
            await refresh()
        }
    }

    func clearMemory() {
        guard let engine else { return }
        Task {
            try? await engine.memory.forgetAll()
            await refresh()
        }
    }

    /// Ends the island's activity: quietly when the panel shows the answer, with the panda and the answer when it doesn't.
    private func report(_ activity: LiveActivity, failure: MouldError?) {
        if self.activity === activity { self.activity = nil }
        switch failure {
        case nil:
            activity.finish(nil)
            guard !MindPanel.shared.isOpen, let answer = conversation.lastAnswer, !answer.isEmpty else { return }
            var notice = IslandNotice(symbol: "sparkles", tint: Palette.accent, title: MindPhrases.done.text, detail: String(answer.prefix(140)),
                                      style: .success, duration: 7, actionTitle: MindPhrases.open.text, action: { MindPanel.shared.open() })
            notice.mascot = Suite.shared.settings.islandPanda ? .done : nil
            Suite.shared.notify(notice)
        case .cancelled?, .declined?:
            activity.finish(nil)
        case let failure?:
            activity.fail(MindPhrases.error(failure))
        }
    }

    // MARK: Consent

    /// Asks the person: in the panel when it's open, otherwise in the island with the panda.
    func ask(_ request: ConfirmationRequest) async -> ConfirmationDecision {
        await withCheckedContinuation { continuation in
            waiting[request.id] = continuation
            conversation.confirm(request)
            if !MindPanel.shared.isOpen { notifyConsent(request) }
        }
    }

    func decide(_ id: String, _ decision: ConfirmationDecision) {
        guard let continuation = waiting.removeValue(forKey: id) else { return }
        conversation.answered(id, decision)
        continuation.resume(returning: decision)
    }

    /// The panel closed with a question still open: the island asks it instead.
    func panelClosed() {
        for request in conversation.pendingConsent where waiting[request.id] != nil { notifyConsent(request) }
    }

    /// A finished or stopped task can't be waiting for an answer any more.
    private func settle(_ taskID: String) {
        for request in conversation.pendingConsent where request.taskID == taskID { decide(request.id, .declined) }
    }

    private func notifyConsent(_ request: ConfirmationRequest) {
        let title = conversation.items.last { $0.id == request.id }?.text ?? request.title
        let first = request.items.first
        let detail = first.flatMap { item in item.preview.changes.first.map(MindPhrases.change) } ?? first?.preview.summary ?? ""
        var notice = IslandNotice(symbol: "hand.raised.fill", tint: Palette.accent, title: title, detail: detail, style: .alert, duration: 170,
                                  actionTitle: MindPhrases.allow.text, action: { MindHost.shared.decide(request.id, .approved) })
        notice.secondTitle = MindPhrases.deny.text
        notice.second = { MindHost.shared.decide(request.id, .declined) }
        notice.dismissed = { MindHost.shared.decide(request.id, .declined) }
        notice.mascot = Suite.shared.settings.islandPanda ? .ask : nil
        notice.urgent = true
        Suite.shared.notify(notice)
    }

    // MARK: The local model

    func downloadRecommended() {
        guard download == nil else { return }
        let model = LocalModels.recommended
        downloading = 0
        downloadProblem = nil
        let job = ModelDownload(url: model.url, to: Self.modelsFolder.appendingPathComponent(model.file), bytes: model.bytes, sha256: model.sha256,
                                progress: { fraction in Task { @MainActor in MindHost.shared.progressed(fraction) } },
                                done: { problem in Task { @MainActor in MindHost.shared.downloaded(problem) } })
        download = job
        job.start()
    }

    func cancelDownload() {
        download?.cancel()
        download = nil
        downloading = nil
    }

    private func progressed(_ fraction: Double) {
        guard download != nil else { return }
        downloading = fraction
    }

    private func downloaded(_ problem: ModelDownload.Problem?) {
        guard download != nil else { return }
        download = nil
        downloading = nil
        switch problem {
        case nil: reloadLocal()
        case .checksum?: downloadProblem = MindPhrases.checksum.text
        case .failed(let message)?: downloadProblem = MindPhrases.downloadFailed.text + (message.isEmpty ? "" : ": " + message)
        }
    }

    // MARK: Events from the engine

    private func listen(_ pulse: Pulse) {
        listener?.cancel()
        let events = pulse.events(topics: [.taskProgress, .confirmationAnswered, .modelLoaded, .modelUnloaded, .memoryChanged])
        listener = Task { [weak self] in
            for await event in events { self?.handle(event) }
        }
    }

    private func handle(_ event: Pulse.Event) {
        switch event.topic {
        case .taskProgress:
            if let fraction = event.payload["fraction"]?.number, let task = event.taskID, task == conversation.running {
                activity?.update(progress: fraction)
            }
        case .confirmationAnswered:
            // Unanswered until the runtime gave up: the card and the island's question go.
            if let id = event.payload["request"]?.string, event.payload["decision"]?.string == "expired" { decide(id, .expired) }
        default:
            Task { await refresh() }
        }
    }
}

/// The engine's way to ask the person: it hands every request to the host on the main thread.
struct MindBroker: ConfirmationBroker {
    func confirm(_ request: ConfirmationRequest) async -> ConfirmationDecision {
        await MindHost.shared.ask(request)
    }
}

/// What a button's tool found, said in the person's language from the tool's numbers rather than its English words.
enum MindReport {
    @MainActor static func describe(_ tool: ToolName, _ output: ToolOutput) -> String {
        let value = output.value
        switch tool {
        case "mac.health":
            var lines: [String] = []
            let resources = value["resources"]
            let free = resources?["memoryAvailableGB"]?.number ?? 0, total = resources?["memoryTotalGB"]?.number ?? 0
            let cpu = resources?["cpuLoadPercent"]?.number ?? 0
            let diskFree = value["diskFreeGB"]?.number ?? 0, diskTotal = value["diskTotalGB"]?.number ?? 0
            var issues: [String] = []
            if total > 0, free < total * 0.1 { issues.append(MindPhrases.memoryFull.text) }
            if cpu > 75 { issues.append(MindPhrases.cpuBusy.text) }
            if let thermal = resources?["thermal"]?.string, thermal == "serious" || thermal == "critical" { issues.append(MindPhrases.hot.text) }
            if resources?["onBattery"]?.bool == true, let battery = resources?["batteryPercent"]?.number, battery < 20 { issues.append(MindPhrases.batteryLow.text) }
            if diskTotal > 0, diskFree < max(10, diskTotal * 0.08) { issues.append(MindPhrases.diskLow.text) }
            lines.append(issues.isEmpty ? MindPhrases.allFine.text : issues.joined(separator: " "))
            lines.append(MindPhrases.memoryLine(free, total))
            lines.append(MindPhrases.cpuLine(Int(cpu)))
            if diskTotal > 0 { lines.append(MindPhrases.diskLine(diskFree, diskTotal)) }
            if let battery = resources?["batteryPercent"]?.number { lines.append(MindPhrases.batteryLine(Int(battery))) }
            let heavy = (value["topMemory"]?.array ?? []).prefix(3).compactMap { item -> String? in
                guard let name = item["name"]?.string else { return nil }
                return "\(name) (\(MindPhrases.gigabytes((item["memoryMB"]?.number ?? 0) / 1024)))"
            }
            if !heavy.isEmpty { lines.append("\(MindPhrases.heaviest.text): \(heavy.joined(separator: ", "))") }
            // Per-core percent, as Activity Monitor counts it: 100 is one core fully busy.
            if let top = value["topCPU"]?.array?.first, let name = top["name"]?.string, let share = top["cpuPercent"]?.number, share > 50 {
                lines.append(MindPhrases.busiest(name, cores: share / 100))
            }
            return lines.joined(separator: "\n")
        case "files.sort_folder":
            let moved = value["moved"]?.array?.count ?? 0
            return moved == 0 ? MindPhrases.nothingToSort.text : MindPhrases.sorted(moved)
        case "calendar.upcoming":
            let events = value["events"]?.array ?? []
            guard !events.isEmpty else { return Suite.shared.calendar.access == .granted ? MindPhrases.noMeetings.text : MindPhrases.noCalendar.text }
            let iso = ISO8601DateFormatter()
            let locale = Suite.shared.language.locale
            return events.prefix(8).compactMap { event -> String? in
                guard let title = event["title"]?.string, let start = event["start"]?.string.flatMap(iso.date(from:)) else { return nil }
                let day = Calendar.current.isDateInToday(start) ? "" : start.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(locale)) + ", "
                let place = event["online"]?.bool == true ? " · Zoom/Meet" : (event["location"]?.string).map { " · \($0)" } ?? ""
                return "• \(day)\(start.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(locale))) \(title)\(place)"
            }.joined(separator: "\n")
        case "agents.status":
            let agents = value["agents"]?.array ?? []
            guard !agents.isEmpty else { return MindPhrases.noAgents.text }
            return agents.compactMap { agent -> String? in
                guard let name = agent["agent"]?.string else { return nil }
                let project = agent["project"]?.string
                let minutes = agent["minutes"]?.int
                return "• " + MindPhrases.agentLine(name, working: agent["working"]?.bool == true, project: project, minutes: minutes)
            }.joined(separator: "\n")
        case "savisul.feature":
            guard let id = value["id"]?.string, let on = value["on"]?.bool else { return MindPhrases.done.text }
            return MindPhrases.switched(MindPhrases.featureName(id), on: on)
        case "clipboard.search":
            let items = value["items"]?.array ?? []
            guard !items.isEmpty else { return MindPhrases.nothingCopied.text }
            return items.prefix(8).compactMap { $0["text"]?.string.map { "• " + String($0.prefix(140)) } }.joined(separator: "\n")
        default:
            return Suite.shared.language == .en ? output.summary ?? MindPhrases.done.text : MindPhrases.done.text
        }
    }
}

/// Downloads a model file to a temporary name, checks it is exactly the expected file, then moves it into place.
final class ModelDownload: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    enum Problem: Error { case checksum, failed(String) }

    private let url: URL
    private let target: URL
    private let bytes: Int64
    private let sha256: String
    private let progress: @Sendable (Double) -> Void
    private let done: @Sendable (Problem?) -> Void
    private let lock = NSLock()
    private var session: URLSession?
    private var finished = false
    private var attempts = 0

    init(url: URL, to target: URL, bytes: Int64, sha256: String, progress: @escaping @Sendable (Double) -> Void,
         done: @escaping @Sendable (Problem?) -> Void) {
        self.url = url
        self.target = target
        self.bytes = bytes
        self.sha256 = sha256
        self.progress = progress
        self.done = done
    }

    func start() {
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        lock.withLock { self.session = session }
        session.downloadTask(with: url).resume()
    }

    func cancel() {
        lock.withLock {
            finished = true
            session?.invalidateAndCancel()
        }
    }

    private func end(_ problem: Problem?) {
        let first = lock.withLock { () -> Bool in
            defer { finished = true }
            return !finished
        }
        if first { done(problem) }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData _: Int64, totalBytesWritten written: Int64,
                    totalBytesExpectedToWrite expected: Int64) {
        progress(Double(written) / Double(expected > 0 ? expected : bytes))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        defer { session.finishTasksAndInvalidate() }
        if let http = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            end(.failed("HTTP \(http.statusCode)"))
            return
        }
        // The file is a model llama.cpp will parse: anything but the exact expected bytes is thrown away.
        guard Self.sha256(of: location) == sha256 else {
            try? FileManager.default.removeItem(at: location)
            end(.checksum)
            return
        }
        do {
            let manager = FileManager.default
            try manager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            if manager.fileExists(atPath: target.path) { try manager.removeItem(at: target) }
            try manager.moveItem(at: location, to: target)
            end(nil)
        } catch {
            end(.failed(error.localizedDescription))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        guard let error, (error as NSError).code != NSURLErrorCancelled else { return }
        // Gigabytes over a connection that drops now and then: it goes on from where it stopped, a few times.
        if let data = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data,
           lock.withLock({ () -> Bool in attempts += 1; return attempts <= 3 && !finished }) {
            session.downloadTask(withResumeData: data).resume()
            return
        }
        end(.failed(error.localizedDescription))
    }

    static func sha256(of file: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try? handle.read(upToCount: 8 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
#endif
