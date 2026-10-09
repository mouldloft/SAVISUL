import AppKit
import CoreGraphics
import Observation

enum AppCategory: String, Codable {
    case editor, assistant, other
}

struct AppUsage: Codable, Equatable, Identifiable {
    var bundleID: String
    var name: String
    var seconds: Double
    var latin: Int
    var other: Int
    var keystrokes: Int
    var category: AppCategory

    var id: String { bundleID }
    var characters: Int { latin + other }
    var tokens: Int { Int((Double(latin) / 4 + Double(other) / 2.2).rounded()) }

    init(bundleID: String, name: String, seconds: Double = 0, latin: Int = 0, other: Int = 0, keystrokes: Int = 0,
         category: AppCategory? = nil) {
        self.bundleID = bundleID
        self.name = name
        self.seconds = seconds
        self.latin = latin
        self.other = other
        self.keystrokes = keystrokes
        self.category = category ?? AppClassifier.category(bundleID: bundleID, name: name)
    }

    private enum CodingKeys: String, CodingKey {
        case bundleID, name, seconds, latin, other, keystrokes, characters
    }

    /// Also reads files from the first build, which stored one `characters` total.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bundleID = try container.decode(String.self, forKey: .bundleID)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? bundleID
        seconds = try container.decodeIfPresent(Double.self, forKey: .seconds) ?? 0
        let legacy = try container.decodeIfPresent(Int.self, forKey: .characters) ?? 0
        latin = try container.decodeIfPresent(Int.self, forKey: .latin) ?? legacy
        other = try container.decodeIfPresent(Int.self, forKey: .other) ?? 0
        keystrokes = try container.decodeIfPresent(Int.self, forKey: .keystrokes) ?? 0
        category = AppClassifier.category(bundleID: bundleID, name: name)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(bundleID, forKey: .bundleID)
        try container.encode(name, forKey: .name)
        try container.encode(seconds, forKey: .seconds)
        try container.encode(latin, forKey: .latin)
        try container.encode(other, forKey: .other)
        try container.encode(keystrokes, forKey: .keystrokes)
    }
}

enum AppClassifier {
    static func category(bundleID: String, name: String) -> AppCategory {
        let id = bundleID.lowercased()
        let folded = name.lowercased()
        if isEditor(id: id, name: folded) { return .editor }
        if isAssistant(id: id, name: folded) { return .assistant }
        return .other
    }

    private static func isEditor(id: String, name: String) -> Bool {
        if id.hasPrefix("com.jetbrains.") || id.hasPrefix("com.todesktop.") { return true }
        let ids: Set<String> = [
            "com.microsoft.vscode", "com.microsoft.vscodeinsiders", "com.visualstudio.code.oss", "com.vscodium",
            "com.apple.dt.xcode", "dev.zed.zed", "dev.zed.zed-preview", "com.sublimetext.4", "com.sublimetext.3",
            "com.panic.nova", "com.exafunction.windsurf", "ai.windsurf.windsurf", "com.google.android.studio",
            "com.barebones.bbedit", "com.macromates.textmate", "io.neovim.nvim", "org.vim.macvim", "dev.kiro.desktop",
            "com.trae.app", "com.google.antigravity"
        ]
        if ids.contains(id) { return true }
        let names: Set<String> = [
            "cursor", "visual studio code", "code", "xcode", "zed", "windsurf", "nova", "sublime text",
            "android studio", "vscodium", "fleet", "bbedit", "textmate", "neovim", "macvim", "intellij idea",
            "pycharm", "webstorm", "clion", "goland", "rustrover", "datagrip", "rider", "rubymine", "phpstorm",
            "kiro", "trae", "antigravity"
        ]
        return names.contains(name)
    }

    private static func isAssistant(id: String, name: String) -> Bool {
        let ids: Set<String> = [
            "com.openai.chat", "com.openai.codex", "com.anthropic.claudefordesktop", "ai.perplexity.mac",
            "ai.perplexity.comet", "com.google.gemini", "ai.x.grok", "com.deepseek.chat", "ai.elementlabs.lmstudio",
            "com.electron.ollama", "app.msty.app", "jan.ai.app"
        ]
        if ids.contains(id) { return true }
        let markers = ["chatgpt", "claude", "perplexity", "comet", "gemini", "grok", "deepseek", "lm studio", "ollama", "msty", "codex"]
        return markers.contains { name.contains($0) }
    }
}

@MainActor
@Observable
final class ActivityTracker {
    var today: [AppUsage] = []
    var week: [AppUsage] = []
    var typingActive = false
    var typingFailed = false

    @ObservationIgnored private var days: [String: [String: AppUsage]] = [:]
    @ObservationIgnored private var current: (bundleID: String, name: String)?
    @ObservationIgnored private var lastTick = Date()
    @ObservationIgnored private var paused = false
    @ObservationIgnored private var dirty = false
    @ObservationIgnored private var unsavedTicks = 0
    @ObservationIgnored private var hiddenTicks = 0
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private let persist: Bool
    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private let io = DispatchQueue(label: "com.savisul.activity", qos: .utility)
    @ObservationIgnored private let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    init(persist: Bool) {
        self.persist = persist
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SAVISUL", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        fileURL = support.appendingPathComponent("activity.json")
        if persist { load() }
    }

    func start() {
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil,
                                               queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { self?.activate(app) }
        })
        observers.append(workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.pause(true) }
        })
        observers.append(workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.pause(false) }
        })
        let distributed = DistributedNotificationCenter.default()
        observers.append(distributed.addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil,
                                                 queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.pause(true) }
        })
        observers.append(distributed.addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil,
                                                 queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.pause(false) }
        })
        activate(NSWorkspace.shared.frontmostApplication)
        publish()
    }

    func enableTyping() {
        if KeystrokeCounter.shared.start() {
            typingActive = true
            typingFailed = false
        } else {
            typingActive = false
            typingFailed = true
        }
    }

    private func pause(_ paused: Bool) {
        self.paused = paused
        lastTick = Date()
    }

    private func activate(_ app: NSRunningApplication?) {
        guard let app, app.processIdentifier != getpid() else { return }
        let id = app.bundleIdentifier ?? "process.\(app.localizedName ?? "\(app.processIdentifier)")"
        current = (id, app.localizedName ?? id)
    }

    func tick(visible: Bool) {
        let now = Date()
        let delta = now.timeIntervalSince(lastTick)
        lastTick = now
        let typed = KeystrokeCounter.shared.drain()
        guard let current, !paused else { return }
        let anyInput = CGEventType(rawValue: ~0)!
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
        var changed = false
        if delta > 0, delta < 3, idle < 120 {
            record(current) { $0.seconds += delta }
            changed = true
        }
        if typed.keystrokes > 0 {
            record(current) {
                $0.latin += typed.latin
                $0.other += typed.other
                $0.keystrokes += typed.keystrokes
            }
            changed = true
        }
        guard changed else { return }
        dirty = true
        unsavedTicks += 1
        hiddenTicks += 1
        if visible || hiddenTicks >= 15 {
            hiddenTicks = 0
            publish()
        }
        if unsavedTicks >= 30 { save() }
    }

    private func record(_ app: (bundleID: String, name: String), _ change: (inout AppUsage) -> Void) {
        let key = dayFormatter.string(from: Date())
        var usage = days[key]?[app.bundleID] ?? AppUsage(bundleID: app.bundleID, name: app.name)
        usage.name = app.name
        change(&usage)
        days[key, default: [:]][app.bundleID] = usage
    }

    func publish() {
        let todayRows = Array((days[dayFormatter.string(from: Date())] ?? [:]).values).sorted { $0.seconds > $1.seconds }
        var merged: [String: AppUsage] = [:]
        for key in recentKeys(7) {
            for usage in (days[key] ?? [:]).values {
                if var existing = merged[usage.bundleID] {
                    existing.seconds += usage.seconds
                    existing.latin += usage.latin
                    existing.other += usage.other
                    existing.keystrokes += usage.keystrokes
                    merged[usage.bundleID] = existing
                } else {
                    merged[usage.bundleID] = usage
                }
            }
        }
        let weekRows = Array(merged.values).sorted { $0.seconds > $1.seconds }
        if todayRows != today { today = todayRows }
        if weekRows != week { week = weekRows }
    }

    func rows(_ range: WorkRange) -> [AppUsage] {
        range == .today ? today : week
    }

    func seconds(_ range: WorkRange, _ category: AppCategory) -> Double {
        rows(range).filter { $0.category == category }.reduce(0) { $0 + $1.seconds }
    }

    func typing(_ range: WorkRange) -> (characters: Int, tokens: Int) {
        let rows = rows(range).filter { $0.category != .other }
        return (rows.reduce(0) { $0 + $1.characters }, rows.reduce(0) { $0 + $1.tokens })
    }

    private func recentKeys(_ count: Int) -> [String] {
        let calendar = Calendar.current
        return (0..<count).compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: Date()).map { dayFormatter.string(from: $0) }
        }
    }

    // MARK: Storage

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([String: [String: AppUsage]].self, from: data) else { return }
        days = decoded
    }

    func save(synchronously: Bool = false) {
        guard persist, dirty else { return }
        dirty = false
        unsavedTicks = 0
        let keep = Set(recentKeys(30))
        days = days.filter { keep.contains($0.key) }
        guard let data = try? JSONEncoder().encode(days) else { return }
        let url = fileURL
        if synchronously {
            try? data.write(to: url, options: .atomic)
        } else {
            io.async { try? data.write(to: url, options: .atomic) }
        }
    }

    // MARK: Preview data

    func seedPreview() {
        let key = dayFormatter.string(from: Date())
        let rows = [
            AppUsage(bundleID: "com.todesktop.230313mzl4w4u92", name: "Cursor", seconds: 9_420, latin: 15_880, other: 4_210, keystrokes: 21_900),
            AppUsage(bundleID: "com.microsoft.VSCode", name: "Visual Studio Code", seconds: 2_160, latin: 2_940, other: 120, keystrokes: 3_400),
            AppUsage(bundleID: "com.apple.dt.Xcode", name: "Xcode", seconds: 1_310, latin: 1_220, keystrokes: 1_380),
            AppUsage(bundleID: "com.openai.chat", name: "ChatGPT", seconds: 1_870, latin: 1_430, other: 2_380, keystrokes: 4_100),
            AppUsage(bundleID: "com.anthropic.claudefordesktop", name: "Claude", seconds: 960, latin: 820, other: 1_060, keystrokes: 2_050),
            AppUsage(bundleID: "com.google.Chrome", name: "Google Chrome", seconds: 3_350),
            AppUsage(bundleID: "ru.keepcoder.Telegram", name: "Telegram", seconds: 1_420),
            AppUsage(bundleID: "com.apple.finder", name: "Finder", seconds: 610)
        ]
        days = [key: Dictionary(uniqueKeysWithValues: rows.map { ($0.bundleID, $0) })]
        publish()
    }
}

/// Counts keys from a listen-only event tap. Text is never stored, only per-script character counts.
final class KeystrokeCounter: @unchecked Sendable {
    static let shared = KeystrokeCounter()
    nonisolated(unsafe) static var tap: CFMachPort?

    private let lock = NSLock()
    private var latin = 0
    private var other = 0
    private var keystrokes = 0
    private var running = false

    func start() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if running { return true }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
                                          eventsOfInterest: mask, callback: keystrokeCallback, userInfo: nil) else {
            return false
        }
        KeystrokeCounter.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        running = true
        return true
    }

    func drain() -> (latin: Int, other: Int, keystrokes: Int) {
        lock.lock()
        defer { lock.unlock() }
        let counts = (latin: latin, other: other, keystrokes: keystrokes)
        latin = 0
        other = 0
        keystrokes = 0
        return counts
    }

    fileprivate func add(latin: Int, other: Int) {
        lock.lock()
        self.latin += latin
        self.other += other
        keystrokes += 1
        lock.unlock()
    }
}

private func keystrokeCallback(_ proxy: CGEventTapProxy, _ type: CGEventType, _ event: CGEvent,
                               _ userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let tap = KeystrokeCounter.tap { CGEvent.tapEnable(tap: tap, enable: true) }
        return Unmanaged.passUnretained(event)
    }
    guard type == .keyDown, event.getIntegerValueField(.keyboardEventAutorepeat) == 0 else {
        return Unmanaged.passUnretained(event)
    }
    let flags = event.flags
    if flags.contains(.maskCommand) || flags.contains(.maskControl) { return Unmanaged.passUnretained(event) }
    var length = 0
    var buffer = [UniChar](repeating: 0, count: 8)
    event.keyboardGetUnicodeString(maxStringLength: 8, actualStringLength: &length, unicodeString: &buffer)
    var latin = 0
    var other = 0
    for unit in buffer.prefix(length) where unit >= 32 && unit != 127 {
        if unit < 128 { latin += 1 } else { other += 1 }
    }
    KeystrokeCounter.shared.add(latin: latin, other: other)
    return Unmanaged.passUnretained(event)
}
