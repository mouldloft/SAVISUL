import Foundation
import SwiftUI

enum AgentKind: String, CaseIterable, Sendable {
    case claude, codex, cursor, opencode, copilot

    var title: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex"
        case .cursor: "Cursor"
        case .opencode: "OpenCode"
        case .copilot: "Copilot"
        }
    }

    var short: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        case .cursor: "Cursor"
        case .opencode: "OpenCode"
        case .copilot: "Copilot"
        }
    }

    var tint: Color {
        switch self {
        case .claude: Color(red: 0.85, green: 0.47, blue: 0.34)
        case .codex: Color(red: 0.62, green: 0.80, blue: 0.98)
        case .cursor: Color(red: 0.88, green: 0.88, blue: 0.90)
        case .opencode: Color(red: 0.98, green: 0.82, blue: 0.42)
        case .copilot: Color(red: 0.72, green: 0.58, blue: 0.98)
        }
    }

    var symbol: String {
        switch self {
        case .claude: "asterisk"
        case .codex: "hexagon"
        case .cursor: "cursorarrow.rays"
        case .opencode: "chevron.left.forwardslash.chevron.right"
        case .copilot: "airplane"
        }
    }
}

struct AgentLimit: Equatable, Sendable, Identifiable {
    enum Window: Hashable, Sendable {
        case minutes(Int)
        case days(Int)
    }

    var id: Window { window }
    var window: Window
    var used: Double?
    var resets: Date?
    var tokens: Int?
}

struct AgentStatus: Equatable, Sendable, Identifiable {
    var id: AgentKind { kind }
    let kind: AgentKind
    var installed = false
    var working = false
    var runs = 0
    var since: Date?
    var project: String?
    /// The full folder the newest session runs in, so a new task can start there.
    var projectPath: String?
    var model: String?
    var task: String?
    /// Tokens the model actually processed today: input, output and cache writes.
    var tokensToday = 0
    /// Cache reads today. Kept apart: each turn re-reads the whole context, so they dwarf real usage.
    var cacheToday = 0
    var costToday: Double?
    /// Code the agent wrote today inside its project: lines added and removed, files created and edited.
    var code = CodeTally()
    /// Where the newest session runs: the terminal, VS Code or Cursor.
    var surface: AgentSurface?
    /// Today's usage split by where it ran, for the Work tab's editor rows.
    var surfaces: [AgentSurface: SurfaceUsage] = [:]
    /// The same over the last seven days, for the Work tab's week view.
    var tokensWeek = 0
    var codeWeek = CodeTally()
    var surfacesWeek: [AgentSurface: SurfaceUsage] = [:]
    var limits: [AgentLimit] = []
    var plan: String?
    var lastActive: Date?
    var sessionsToday = 0
    var limitHit = false
    var limitUntil: Date?
}

enum AgentSurface: String, Sendable {
    case terminal, vscode, cursor, desktop

    var title: String {
        switch self {
        case .terminal: "Terminal"
        case .vscode: "VS Code"
        case .cursor: "Cursor"
        case .desktop: "App"
        }
    }
}

/// One agent's usage today inside one surface (an editor or the terminal).
/// Sums a reader's per-day records over the last seven days.
enum AgentWeek {
    static func days(_ now: Date) -> ClosedRange<Int> {
        let today = AgentTime.day(now)
        return (today - 6)...today
    }

    static func surfaces(_ byDay: [Int: [AgentSurface: SurfaceUsage]], now: Date) -> [AgentSurface: SurfaceUsage] {
        var total: [AgentSurface: SurfaceUsage] = [:]
        for day in days(now) {
            for (surface, usage) in byDay[day] ?? [:] { total[surface, default: SurfaceUsage()].add(usage) }
        }
        return total
    }

    static func code(_ byDay: [Int: CodeTally], now: Date) -> CodeTally {
        var total = CodeTally()
        for day in days(now) { if let tally = byDay[day] { total.add(tally) } }
        return total
    }
}

struct SurfaceUsage: Equatable, Sendable {
    var tokens = 0
    var cache = 0
    var code = CodeTally()
    var model: String?
    var last = Date.distantPast

    mutating func add(_ other: SurfaceUsage) {
        tokens += other.tokens
        cache += other.cache
        code.add(other.code)
        if other.last > last {
            last = other.last
            model = other.model ?? model
        }
    }
}

/// Which folders VS Code and Cursor have open, from their own workspace records, so a session
/// started by the shared Claude Code extension can be credited to the right editor.
final class EditorWorkspaces: @unchecked Sendable {
    static let shared = EditorWorkspaces()
    private let lock = NSLock()
    private var folders: [AgentSurface: [(path: String, used: Date)]] = [:]
    private var loaded = Date.distantPast

    func surface(for cwd: String?, fallback: AgentSurface) -> AgentSurface {
        guard let cwd, fallback == .vscode || fallback == .cursor else { return fallback }
        refresh()
        lock.lock()
        defer { lock.unlock() }
        func best(_ surface: AgentSurface) -> Date? {
            folders[surface]?.filter { cwd == $0.path || cwd.hasPrefix($0.path + "/") }.map(\.used).max()
        }
        switch (best(.vscode), best(.cursor)) {
        case (let code?, let cursor?): return cursor > code ? .cursor : .vscode
        case (.some, nil): return .vscode
        case (nil, .some): return .cursor
        default: return fallback
        }
    }

    /// The folder each editor has open most recently, for the Work tab.
    func current(_ surface: AgentSurface) -> String? {
        refresh()
        lock.lock()
        defer { lock.unlock() }
        return folders[surface]?.max { $0.used < $1.used }?.path
    }

    private func refresh() {
        lock.lock()
        let stale = Date().timeIntervalSince(loaded) > 60
        if stale { loaded = Date() }
        lock.unlock()
        guard stale else { return }
        let support = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        var next: [AgentSurface: [(String, Date)]] = [:]
        for (surface, app) in [(AgentSurface.vscode, "Code"), (.cursor, "Cursor")] {
            let storage = support.appendingPathComponent("\(app)/User/workspaceStorage")
            let items = (try? FileManager.default.contentsOfDirectory(at: storage, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
            var list: [(String, Date)] = []
            for item in items {
                let file = item.appendingPathComponent("workspace.json")
                guard let data = try? Data(contentsOf: file), let object = AgentLog.object(data),
                      let folder = object["folder"] as? String, let url = URL(string: folder), url.isFileURL else { continue }
                let used = (try? item.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                list.append((url.path, used))
            }
            next[surface] = list
        }
        lock.lock()
        folders = next
        lock.unlock()
    }
}

/// Lines and files an agent changed. New files count once even when edited again later.
struct CodeTally: Equatable, Sendable {
    var added = 0
    var removed = 0
    var created: Set<String> = []
    var edited: Set<String> = []

    var isEmpty: Bool { added == 0 && removed == 0 && created.isEmpty && edited.isEmpty }
    var filesCreated: Int { created.count }
    var filesEdited: Int { edited.subtracting(created).count }

    mutating func add(_ other: CodeTally) {
        added += other.added
        removed += other.removed
        created.formUnion(other.created)
        edited.formUnion(other.edited)
    }

    /// Counts a unified patch: `+` and `-` lines, and `*** Add File:` / `*** Update File:` headers (Codex apply_patch).
    mutating func addPatch(_ patch: String, within root: String?) {
        var file: String?
        var counting = false
        for raw in patch.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.hasSuffix("\r") ? raw.dropLast() : raw
            if line.hasPrefix("*** Add File: ") {
                file = String(line.dropFirst(14))
                counting = Self.inside(file, root)
                if counting, let file { created.insert(file) }
            } else if line.hasPrefix("*** Update File: ") {
                file = String(line.dropFirst(17))
                counting = Self.inside(file, root)
                if counting, let file { edited.insert(file) }
            } else if line.hasPrefix("*** ") {
                counting = false
            } else if counting, line.hasPrefix("+") {
                added += 1
            } else if counting, line.hasPrefix("-") {
                removed += 1
            }
        }
    }

    /// Code outside the session's project (scratch files, temp folders) doesn't count as project code.
    static func inside(_ path: String?, _ root: String?) -> Bool {
        guard let path, !path.isEmpty else { return false }
        guard let root, !root.isEmpty, root != NSHomeDirectory() else { return !path.hasPrefix("/tmp") && !path.hasPrefix("/private/") }
        if !path.hasPrefix("/") { return true }
        return path == root || path.hasPrefix(root.hasSuffix("/") ? root : root + "/")
    }
}

struct AgentFinish: Equatable, Sendable {
    var kind: AgentKind
    var project: String?
    var duration: TimeInterval
    var limitHit = false
    var error: String?
    var task: String?
}

/// Reads a log file incrementally: each call returns only the complete lines written since the last call.
final class LogTail {
    let url: URL
    private(set) var offset: UInt64 = 0
    private(set) var modified: Date = .distantPast
    private var carry = Data()

    init(_ url: URL) { self.url = url }

    func changed() -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]) else { return false }
        let date = values.contentModificationDate ?? .distantPast
        let size = UInt64(values.fileSize ?? 0)
        return date != modified || size != offset + UInt64(carry.count)
    }

    /// Every complete line written since the last call. Reads in chunks, so a large session log
    /// is counted whole (a tail-only read made totals drop after each relaunch) without loading it at once.
    func forEachLine(limit: Int = 1 << 31, chunk: Int = 8 << 20, _ body: (Data) -> Void) {
        guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]) else { return }
        modified = values.contentModificationDate ?? Date()
        let size = UInt64(values.fileSize ?? 0)
        let consumed = offset + UInt64(carry.count)
        if size < consumed {
            offset = 0
            carry = Data()
        }
        guard size > offset + UInt64(carry.count), let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }
        var position = offset + UInt64(carry.count)
        if size - position > UInt64(limit) {
            position = size - UInt64(limit)
            carry = Data()
        }
        try? handle.seek(toOffset: position)
        while position < size {
            let want = Int(min(UInt64(chunk), size - position))
            guard let block = try? handle.read(upToCount: want), !block.isEmpty else { break }
            position += UInt64(block.count)
            var data = carry
            data.append(block)
            var lineStart = data.startIndex
            while let newline = data[lineStart...].firstIndex(of: 0x0A) {
                if newline > lineStart { body(Data(data[lineStart..<newline])) }
                lineStart = data.index(after: newline)
            }
            carry = Data(data[lineStart...])
        }
        offset = position - UInt64(carry.count)
    }

    func read(limit: Int = 1 << 31) -> [Data] {
        var lines: [Data] = []
        forEachLine(limit: limit) { lines.append($0) }
        return lines
    }

    /// The last few kilobytes, for logs where only the newest line matters.
    func tail(bytes: Int = 24_000) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let start = size > UInt64(bytes) ? size - UInt64(bytes) : 0
        try? handle.seek(toOffset: start)
        guard let data = try? handle.readToEnd() else { return nil }
        modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
        offset = size
        return String(decoding: data, as: UTF8.self)
    }
}

enum AgentTime {
    nonisolated(unsafe) private static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    nonisolated(unsafe) private static let plain = ISO8601DateFormatter()

    static func parse(_ value: Any?) -> Date? {
        if let number = value as? Double { return Date(timeIntervalSince1970: number > 10_000_000_000 ? number / 1000 : number) }
        guard let text = value as? String else { return nil }
        return fractional.date(from: text) ?? plain.date(from: text)
    }

    /// The local calendar day as a running number. Era ordinality ignores daylight saving time, which
    /// moved midnight to 01:00 all summer and booked that hour's tokens to the day before.
    static func day(_ date: Date) -> Int {
        let local = date.timeIntervalSince1970 + Double(TimeZone.current.secondsFromGMT(for: date))
        return Int((local / 86_400).rounded(.down))
    }
}

/// API list prices per million tokens, to show what a subscription session would have cost.
enum AgentPricing {
    struct Rate {
        var input: Double
        var output: Double
        var cacheRead: Double
        /// Five-minute cache writes; one-hour writes (what Claude Code uses) cost twice the input price.
        var cacheWrite: Double
        var cacheWriteHour: Double = 0
    }

    /// Anthropic list prices per million tokens. Cache reads are 0.1× input except on the models that cut them
    /// further (Opus 5.5 at 0.05×, Fable/Mythos 5.1 at 0.025×).
    static func claude(_ model: String) -> Rate {
        let name = model.lowercased()
        func rate(_ input: Double, _ output: Double, read: Double? = nil) -> Rate {
            Rate(input: input, output: output, cacheRead: read ?? input * 0.1, cacheWrite: input * 1.25, cacheWriteHour: input * 2)
        }
        if name.contains("fable-5-1") || name.contains("mythos-5-1") { return rate(10, 50, read: 0.25) }
        if name.contains("fable") || name.contains("mythos") { return rate(10, 50) }
        if name.contains("opus") {
            if name.contains("opus-5-5") { return rate(4, 20, read: 0.2) }
            let legacy = name.contains("opus-4-1") || name.contains("opus-4-2025") || name.contains("opus-4@") || name.contains("3-opus") || name.hasSuffix("opus-4")
            return legacy ? rate(15, 75) : rate(5, 25)
        }
        if name.contains("sonnet") {
            return name.contains("sonnet-5") ? rate(2, 10) : rate(3, 15)
        }
        if name.contains("haiku") {
            if name.contains("haiku-4") { return rate(1, 5) }
            return name.contains("3-5") ? rate(0.8, 4) : rate(0.25, 1.25)
        }
        return rate(3, 15)
    }

    static func openAI(_ model: String) -> Rate {
        let name = model.lowercased()
        if name.contains("mini") { return Rate(input: 0.25, output: 2, cacheRead: 0.025, cacheWrite: 0.25) }
        if name.contains("nano") { return Rate(input: 0.05, output: 0.4, cacheRead: 0.005, cacheWrite: 0.05) }
        return Rate(input: 1.25, output: 10, cacheRead: 0.125, cacheWrite: 1.25)
    }

    static func cost(_ rate: Rate, input: Int, output: Int, cacheRead: Int, cacheWrite: Int, cacheWriteHour: Int = 0) -> Double {
        let hour = rate.cacheWriteHour > 0 ? rate.cacheWriteHour : rate.cacheWrite
        return (Double(input) * rate.input + Double(output) * rate.output + Double(cacheRead) * rate.cacheRead
                + Double(cacheWrite) * rate.cacheWrite + Double(cacheWriteHour) * hour) / 1_000_000
    }
}

enum AgentText {
    /// The first sentence of a prompt, without markup, for a one-line status.
    static func snippet(_ text: String, limit: Int = 90) -> String? {
        var value = text
        if let range = value.range(of: "<user_query>") { value = String(value[range.upperBound...]) }
        if let range = value.range(of: "</user_query>") { value = String(value[..<range.lowerBound]) }
        value = value.replacingOccurrences(of: #"<[^>]{1,80}>"#, with: " ", options: .regularExpression)
        value = value.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " ")
        value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if value.count > limit { value = String(value.prefix(limit - 1)).trimmingCharacters(in: .whitespaces) + "…" }
        return value
    }

    static func project(_ path: String?) -> String? {
        guard let path, !path.isEmpty else { return nil }
        let name = (path as NSString).lastPathComponent
        return name.isEmpty || path == NSHomeDirectory() ? nil : name
    }
}
