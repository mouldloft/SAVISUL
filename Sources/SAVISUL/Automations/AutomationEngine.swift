import AppKit
import IOKit.ps
import Observation

/// Runs automations: watches for their triggers, checks their conditions and does their steps one by one,
/// showing the work around the notch. Everything is local; nothing runs while Automations is off in Features.
@MainActor
@Observable
final class AutomationEngine {
    private(set) var items: [Automation] = []
    private(set) var history: [AutomationRecord] = []
    private(set) var running: Set<UUID> = []

    @ObservationIgnored private var tick: Timer?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var watchers: [String: FolderWatcher] = [:]
    @ObservationIgnored private var outputs: Set<String>?
    @ObservationIgnored private var battery: BatteryState?
    @ObservationIgnored private var minute = -1
    @ObservationIgnored private var fired: [UUID: Date] = [:]
    @ObservationIgnored private var started = false
    @ObservationIgnored private let storeURL: URL?

    /// Tests pass their own file so they never touch the person's automations.
    init(store: URL? = nil) {
        storeURL = store
        if store != nil { load() }
    }

    private var store: URL {
        if let storeURL { return storeURL }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("SAVISUL/automations.json")
    }

    private var active: Bool { Suite.shared.settings.automations }

    // MARK: Lifecycle

    func start() {
        guard !started else { return }
        started = true
        load()
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let id = app?.bundleIdentifier ?? ""
            let name = app?.localizedName ?? id
            MainActor.assumeIsolated { Suite.shared.automations.appChanged(id, name: name, launched: true) }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let id = app?.bundleIdentifier ?? ""
            let name = app?.localizedName ?? id
            MainActor.assumeIsolated { Suite.shared.automations.appChanged(id, name: name, launched: false) }
        })
        tick = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            MainActor.assumeIsolated { Suite.shared.automations.poll() }
        }
        refreshWatchers()
    }

    // MARK: Store

    private func load() {
        guard let data = try? Data(contentsOf: store), let saved = try? JSONDecoder().decode([Automation].self, from: data) else { return }
        items = saved
    }

    private func save() {
        try? FileManager.default.createDirectory(at: store.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(items) { try? data.write(to: store, options: .atomic) }
        refreshWatchers()
    }

    @discardableResult
    func add(_ automation: Automation) -> Automation {
        var fresh = automation
        fresh.id = UUID()
        fresh.lastRun = nil
        fresh.runs = 0
        items.insert(fresh, at: 0)
        save()
        return fresh
    }

    func update(_ automation: Automation) {
        guard let index = items.firstIndex(where: { $0.id == automation.id }), items[index] != automation else { return }
        items[index] = automation
        save()
    }

    func remove(_ id: UUID) {
        items.removeAll { $0.id == id }
        save()
    }

    func setEnabled(_ id: UUID, _ enabled: Bool) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].enabled = enabled
        save()
    }

    /// One watcher per folder that an enabled automation listens to.
    private func refreshWatchers() {
        let folders = Set(items.filter { $0.enabled && $0.trigger.kind == .fileAdded }.map { Self.expand($0.trigger.text) }.filter { !$0.isEmpty })
        for (path, watcher) in watchers where !folders.contains(path) {
            watcher.stop()
            watchers[path] = nil
        }
        for path in folders where watchers[path] == nil {
            let watcher = FolderWatcher(url: URL(fileURLWithPath: path))
            watcher.onAdded = { url in Suite.shared.automations.fileAdded(url) }
            watchers[path] = watcher
        }
    }

    // MARK: Events

    /// Once a second: audio devices, battery and charger, and the clock.
    private func poll() {
        if let audio = Suite.shared.app?.audio {
            let now = Set(audio.outputs.map(\.name))
            if let before = outputs {
                for name in now.subtracting(before) {
                    fire(.deviceConnected, event: AutomationEvent(title: name, values: ["device": name])) { $0.text.isEmpty || name.localizedCaseInsensitiveContains($0.text) }
                }
                for name in before.subtracting(now) {
                    fire(.deviceDisconnected, event: AutomationEvent(title: name, values: ["device": name])) { $0.text.isEmpty || name.localizedCaseInsensitiveContains($0.text) }
                }
            }
            outputs = now
        }
        let seconds = Int(Date().timeIntervalSince1970)
        if seconds % 2 == 0, let state = BatteryState.read() {
            if let before = battery {
                if state.onAC != before.onAC {
                    fire(state.onAC ? .powerConnected : .powerDisconnected, event: event(for: state)) { _ in true }
                }
                fire(.batteryBelow, event: event(for: state)) { state.percent < $0.number && before.percent >= $0.number }
            }
            battery = state
        }
        let components = Calendar.current.dateComponents([.hour, .minute], from: Date())
        let now = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        if now != minute {
            if minute >= 0 {
                let day = Self.weekday(Date())
                fire(.schedule, event: AutomationEvent(title: Self.clock(now))) { $0.number == now && ($0.weekdays.isEmpty || $0.weekdays.contains(day)) }
            }
            minute = now
        }
    }

    private func event(for state: BatteryState) -> AutomationEvent {
        AutomationEvent(title: "\(state.percent)%", values: ["battery": "\(state.percent)%"])
    }

    func appChanged(_ bundleID: String, name: String, launched: Bool) {
        guard !bundleID.isEmpty, bundleID != Bundle.main.bundleIdentifier else { return }
        fire(launched ? .appLaunched : .appQuit, event: AutomationEvent(title: name, values: ["app": name])) { $0.text == bundleID }
    }

    func fileAdded(_ url: URL) {
        let folder = url.deletingLastPathComponent().path
        let ext = url.pathExtension.lowercased()
        fire(.fileAdded, event: AutomationEvent(title: url.lastPathComponent, files: [url], values: ["file": url.lastPathComponent])) { trigger in
            guard Self.expand(trigger.text) == folder else { return false }
            let wanted = Self.extensions(trigger.extensions)
            return wanted.isEmpty || wanted.contains(ext)
        }
    }

    /// Called by the agent monitor when a run ends.
    func agentFinished(_ finish: AgentFinish) {
        let project = finish.project ?? ""
        let event = AutomationEvent(title: [finish.kind.short, project].filter { !$0.isEmpty }.joined(separator: " · "), text: finish.task,
                                    values: ["agent": finish.kind.short, "project": project])
        fire(.agentFinished, event: event) { $0.text.isEmpty || $0.text == finish.kind.rawValue }
    }

    private func fire(_ kind: AutomationTrigger.Kind, event: AutomationEvent, matches: (AutomationTrigger) -> Bool) {
        guard active else { return }
        let now = Date()
        for automation in items where automation.enabled && automation.trigger.kind == kind && matches(automation.trigger) {
            // A trigger that fires twice in a row (a device reconnecting, a file saved twice) runs once.
            if let last = fired[automation.id], now.timeIntervalSince(last) < 3 { continue }
            guard automation.conditions.allSatisfy(passes) else { continue }
            fired[automation.id] = now
            run(automation, event: event)
        }
    }

    // MARK: Conditions

    func passes(_ condition: AutomationCondition) -> Bool {
        switch condition.kind {
        case .batteryBelow: return (BatteryState.read()?.percent).map { $0 < condition.number } ?? false
        case .batteryAbove: return (BatteryState.read()?.percent).map { $0 > condition.number } ?? true
        case .onPower: return BatteryState.read()?.onAC ?? true
        case .onBattery: return !(BatteryState.read()?.onAC ?? true)
        case .appRunning: return !NSRunningApplication.runningApplications(withBundleIdentifier: condition.text).isEmpty
        case .appNotRunning: return NSRunningApplication.runningApplications(withBundleIdentifier: condition.text).isEmpty
        case .timeBetween:
            let components = Calendar.current.dateComponents([.hour, .minute], from: Date())
            let now = (components.hour ?? 0) * 60 + (components.minute ?? 0)
            let start = condition.number
            let end = condition.number2
            return start <= end ? (now >= start && now < end) : (now >= start || now < end)
        case .weekdays:
            return condition.weekdays.isEmpty || condition.weekdays.contains(Self.weekday(Date()))
        case .outputIs:
            return Suite.shared.app?.audio.currentOutput?.name.localizedCaseInsensitiveContains(condition.text) ?? false
        }
    }

    // MARK: Running

    /// Runs the steps in order. Work that takes a moment shows around the notch; a failing step stops the run and says why.
    func run(_ automation: Automation, event: AutomationEvent = .manual) {
        guard !running.contains(automation.id) else { return }
        running.insert(automation.id)
        let box = RunBox()
        if automation.showInIsland {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                MainActor.assumeIsolated {
                    guard !box.done, box.activity == nil else { return }
                    box.activity = Suite.shared.live.start(symbol: automation.trigger.kind.symbol, title: automation.name,
                                                          detail: box.step)
                    box.activity?.update(progress: box.progress, detail: box.step)
                }
            }
        }
        Task { @MainActor in
            var event = event
            var failure: String?
            for (index, step) in automation.steps.enumerated() {
                box.progress = Double(index) / Double(max(automation.steps.count, 1))
                box.step = step.kind.title.text
                box.activity?.update(progress: box.progress, detail: box.step)
                do {
                    try await perform(step, automation: automation, event: &event)
                } catch {
                    failure = "\(step.kind.title.text): \(error.localizedDescription)"
                    break
                }
            }
            box.done = true
            running.remove(automation.id)
            if let failure {
                if let activity = box.activity { activity.fail(failure) } else {
                    Suite.shared.notify(IslandNotice(symbol: "exclamationmark.triangle.fill", tint: Palette.warning, title: automation.name,
                                                     detail: failure, style: .warning, duration: 5))
                }
            } else {
                box.activity?.finish(nil)
            }
            history.insert(AutomationRecord(name: automation.name, date: Date(), ok: failure == nil, detail: failure ?? event.title), at: 0)
            if history.count > 30 { history.removeLast(history.count - 30) }
            if let index = items.firstIndex(where: { $0.id == automation.id }) {
                items[index].lastRun = Date()
                items[index].runs += 1
                save()
            }
        }
    }

    private func perform(_ step: AutomationStep, automation: Automation, event: inout AutomationEvent) async throws {
        let suite = Suite.shared
        switch step.kind {
        case .notice:
            let text = fill(step.text, event)
            suite.notify(IslandNotice(symbol: automation.trigger.kind.symbol, tint: Palette.accent, title: text.isEmpty ? automation.name : text,
                                      detail: text.isEmpty ? nil : automation.name, style: .success, duration: 3.2))
        case .sound:
            NSSound(named: NSSound.Name(step.text.isEmpty ? "Glass" : step.text))?.play()
        case .setVolume:
            guard let audio = suite.app?.audio else { return }
            audio.setVolume(Double(min(max(step.number, 0), 100)) / 100, device: audio.defaultOutput, scope: .output)
        case .switchOutput:
            guard let audio = suite.app?.audio else { return }
            // A device that has just connected can take a moment to accept sound.
            for _ in 0..<10 {
                if let device = audio.outputs.first(where: { $0.name.localizedCaseInsensitiveContains(step.text) }) {
                    audio.select(device.id, scope: .output)
                    try await Task.sleep(nanoseconds: 300_000_000)
                    return
                }
                try await Task.sleep(nanoseconds: 300_000_000)
                audio.reload(force: true)
            }
            throw ActionError.message(AutomationPhrases.noDevice(step.text))
        case .muteMics, .unmuteMics:
            let wanted = step.kind == .muteMics
            if suite.micMuted != wanted { suite.sound.toggleMics() }
        case .openApp:
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: step.text) else {
                throw ActionError.message(AutomationPhrases.noApp(step.label.isEmpty ? step.text : step.label))
            }
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
        case .quitApp:
            NSRunningApplication.runningApplications(withBundleIdentifier: step.text).forEach { $0.terminate() }
        case .openURL:
            guard let url = URL(string: fill(step.text, event).trimmingCharacters(in: .whitespaces)), url.scheme != nil else {
                throw ActionError.message(AutomationPhrases.badLink.text)
            }
            NSWorkspace.shared.open(url)
        case .shortcut:
            let name = step.text.trimmingCharacters(in: .whitespaces)
            let output = await Task.detached(priority: .userInitiated) { Shell.run("/usr/bin/shortcuts", ["run", name], timeout: 120) }.value
            guard output?.status == 0 else { throw ActionError.message(AutomationPhrases.noShortcut(name)) }
        case .feature:
            guard let key = Self.featureKey(step.text) else { return }
            suite.settings[keyPath: key] = step.flag
        case .action:
            guard let action = ActionRegistry.action(step.text) else { throw ActionError.message(AutomationPhrases.noAction.text) }
            var context = ActionContext(text: event.text, files: event.files)
            context.source = .island
            switch await ActionEngine.execute(action, context: context) {
            case .success(.files(let urls)):
                event.files = urls
                event.values["file"] = urls.first?.lastPathComponent ?? ""
            case .success(.text(let text)):
                Clipboard.copy(text)
            case .success:
                break
            case .failure(let error):
                throw error
            }
        case .renameFile:
            guard !event.files.isEmpty else { throw ActionError.message(AutomationPhrases.noFile.text) }
            event.files = try Self.rename(event.files, pattern: step.text)
            event.values["file"] = event.files.first?.lastPathComponent ?? ""
        case .moveFile:
            guard !event.files.isEmpty else { throw ActionError.message(AutomationPhrases.noFile.text) }
            let folder = URL(fileURLWithPath: Self.expand(step.text))
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            event.files = try FileWork.move(event.files, to: folder)
        case .shelf:
            if !event.files.isEmpty { suite.shelf.add(urls: event.files) } else if let text = event.text { suite.shelf.add(text: text) }
        case .wait:
            try await Task.sleep(nanoseconds: UInt64(min(max(step.number, 0), 600)) * 1_000_000_000)
        }
    }

    /// Fills {file}, {agent}, {project}, {device}, {battery} and {app} in a notice.
    private func fill(_ text: String, _ event: AutomationEvent) -> String {
        var result = text
        for (key, value) in event.values { result = result.replacingOccurrences(of: "{\(key)}", with: value) }
        result = result.replacingOccurrences(of: "\\{[a-z]+\\}", with: "", options: .regularExpression)
        return result.trimmingCharacters(in: CharacterSet(charactersIn: " ·")).trimmingCharacters(in: .whitespaces)
    }

    // MARK: Helpers

    static func expand(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "" : ((trimmed as NSString).expandingTildeInPath as NSString).standardizingPath
    }

    static func extensions(_ text: String) -> Set<String> {
        Set(text.lowercased().split(whereSeparator: { ", ;".contains($0) }).map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".")) }.filter { !$0.isEmpty })
    }

    /// 1 = Monday … 7 = Sunday.
    static func weekday(_ date: Date) -> Int {
        let sunday = Calendar(identifier: .gregorian).component(.weekday, from: date)
        return sunday == 1 ? 7 : sunday - 1
    }

    static func clock(_ minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60 % 24, minutes % 60)
    }

    /// Every switch in the Features tab by its id.
    static func featureKey(_ id: String) -> ReferenceWritableKeyPath<SuiteSettings, Bool>? {
        FeatureGroup.all.flatMap { [$0.main] + $0.options }.first { $0.id == id }?.key
    }

    /// "{date} {name}" → "2026-10-07 invoice.pdf". Tokens: {name}, {ext}, {date}, {time}, {n}.
    static func rename(_ files: [URL], pattern: String) throws -> [URL] {
        let template = pattern.trimmingCharacters(in: .whitespaces).isEmpty ? "{date} {name}" : pattern
        let date = DateFormatter()
        date.dateFormat = "yyyy-MM-dd"
        let time = DateFormatter()
        time.dateFormat = "HH.mm"
        let now = Date()
        return try files.enumerated().map { index, url in
            let ext = url.pathExtension
            var name = template.replacingOccurrences(of: "{name}", with: url.deletingPathExtension().lastPathComponent)
                .replacingOccurrences(of: "{date}", with: date.string(from: now))
                .replacingOccurrences(of: "{time}", with: time.string(from: now))
                .replacingOccurrences(of: "{n}", with: "\(index + 1)")
                .replacingOccurrences(of: "/", with: "-")
            let hasExt = name.contains("{ext}")
            name = name.replacingOccurrences(of: "{ext}", with: ext).trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { throw ActionError.phrase(ContextPhrases.nameNeeded) }
            let target = url.deletingLastPathComponent().appendingPathComponent(hasExt || ext.isEmpty ? name : "\(name).\(ext)")
            guard target.path != url.path else { return url }
            let free = ActionFiles.free(target)
            try FileManager.default.moveItem(at: url, to: free)
            return free
        }
    }
}

/// Shared between a run and the delayed activity it may start.
@MainActor
private final class RunBox {
    var activity: LiveActivity?
    var done = false
    var progress = 0.0
    var step: String?
}

struct BatteryState: Equatable {
    var percent: Int
    var onAC: Bool

    /// The internal battery; nil on Macs without one.
    static func read() -> BatteryState? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in list {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
            let current = description[kIOPSCurrentCapacityKey] as? Int ?? 0
            let maximum = max(description[kIOPSMaxCapacityKey] as? Int ?? 100, 1)
            let state = description[kIOPSPowerSourceStateKey] as? String
            return BatteryState(percent: Int((Double(current) / Double(maximum) * 100).rounded()), onAC: state == kIOPSACPowerValue)
        }
        return nil
    }
}

/// Notices files that arrive in a folder, once they've finished arriving.
@MainActor
final class FolderWatcher {
    let url: URL
    var onAdded: ((URL) -> Void)?
    private var source: DispatchSourceFileSystemObject?
    private var known: Set<String> = []
    private var pending: DispatchWorkItem?
    private static let partial: Set<String> = ["crdownload", "download", "part", "partial", "tmp", "opdownload", "filepart"]

    init(url: URL) {
        self.url = url
        known = Set(names())
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.changed() } }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        self.source = source
    }

    func stop() {
        source?.cancel()
        source = nil
        pending?.cancel()
    }

    private func names() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []).filter { !$0.hasPrefix(".") }
    }

    private func changed() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.scan() } }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }

    private func scan() {
        let now = Set(names())
        let added = now.subtracting(known)
        known = now
        for name in added where !Self.partial.contains((name as NSString).pathExtension.lowercased()) && !name.hasPrefix("Unconfirmed ") {
            settle(url.appendingPathComponent(name), size: -1, attempt: 0)
        }
    }

    /// Waits until the file stops growing, so a copy in progress isn't handed on half-written.
    private func settle(_ file: URL, size: Int, attempt: Int) {
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        let current = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        if current == size || attempt > 60 {
            onAdded?(file)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            MainActor.assumeIsolated { self?.settle(file, size: current, attempt: attempt + 1) }
        }
    }
}

enum AutomationPhrases {
    static let title = Phrase("Automations", ru: "Автоматизации", uk: "Автоматизації", fr: "Automatisations")
    static let noFile = Phrase("No file to work on", ru: "Нет файла для этого шага", uk: "Немає файлу для цього кроку", fr: "Aucun fichier à traiter")
    static let badLink = Phrase("The link isn’t valid", ru: "Неверная ссылка", uk: "Неправильне посилання", fr: "Lien invalide")
    static let noAction = Phrase("That action no longer exists", ru: "Такого действия больше нет", uk: "Такої дії більше немає", fr: "Cette action n’existe plus")

    @MainActor static func noDevice(_ name: String) -> String {
        Phrase("“%@” isn’t connected", ru: "«%@» не подключено", uk: "«%@» не підключено", fr: "« %@ » n’est pas connecté")(name)
    }
    @MainActor static func noApp(_ name: String) -> String {
        Phrase("“%@” isn’t installed", ru: "«%@» не установлено", uk: "«%@» не встановлено", fr: "« %@ » n’est pas installé")(name)
    }
    @MainActor static func noShortcut(_ name: String) -> String {
        Phrase("Shortcut “%@” didn’t run. Check its name in the Shortcuts app.", ru: "Быстрая команда «%@» не запустилась. Проверьте название в приложении «Команды».",
               uk: "Швидка команда «%@» не запустилася. Перевірте назву в застосунку «Команди».", fr: "Le raccourci « %@ » n’a pas tourné. Vérifiez son nom dans Raccourcis.")(name)
    }
}
