import Foundation
import SQLite3

/// Reads Cursor's own AI code tracking (~/.cursor/ai-tracking/ai-code-tracking.db): every line its AI
/// wrote, which model wrote it and in which file. Opened read-only; Cursor keeps writing to it meanwhile.
final class CursorTracking: @unchecked Sendable {
    struct Today: Equatable, Sendable {
        var model: String?
        var modelAt: Date?
        var composerLines = 0
        var tabLines = 0
        var files: Set<String> = []
        var created: Set<String> = []

        var lines: Int { composerLines + tabLines }
    }

    static let shared = CursorTracking()

    private let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cursor/ai-tracking/ai-code-tracking.db")
    private let lock = NSLock()
    private var cached = Today()
    private var cachedWeek = Today()
    private var cachedDay = -1
    private var stamp = Date.distantPast
    private var checked = Date.distantPast
    private var births: [String: Date] = [:]

    var available: Bool { FileManager.default.fileExists(atPath: url.path) }

    /// Today's numbers; queries at most every 15 seconds and only when the database changed.
    func today(now: Date = Date()) -> Today {
        lock.lock()
        defer { lock.unlock() }
        let day = AgentTime.day(now)
        guard now.timeIntervalSince(checked) > 15 || day != cachedDay else { return cached }
        checked = now
        let changed = [url, URL(fileURLWithPath: url.path + "-wal")]
            .compactMap { try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }.max() ?? .distantPast
        guard changed != stamp || day != cachedDay else { return cached }
        stamp = changed
        cachedDay = day
        let start = Calendar.current.startOfDay(for: now)
        cached = query(since: start)
        cachedWeek = query(since: Calendar.current.date(byAdding: .day, value: -6, to: start) ?? start)
        return cached
    }

    /// The last seven days, refreshed together with today.
    func week(now: Date = Date()) -> Today {
        _ = today(now: now)
        lock.lock()
        defer { lock.unlock() }
        return cachedWeek
    }

    private func query(since start: Date) -> Today {
        var result = Today()
        var db: OpaquePointer?
        let path = "file:\(url.path)?mode=ro"
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK, let db else {
            sqlite3_close(db)
            return result
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 250)
        let since = Int64(start.timeIntervalSince1970 * 1000)

        rows(db, "SELECT source, COUNT(*) FROM ai_code_hashes WHERE createdAt >= ? GROUP BY source", since) { statement in
            let source = text(statement, 0) ?? ""
            let count = Int(sqlite3_column_int64(statement, 1))
            if source == "tab" { result.tabLines += count } else { result.composerLines += count }
        }
        rows(db, "SELECT DISTINCT fileName FROM ai_code_hashes WHERE createdAt >= ? AND fileName IS NOT NULL", since) { statement in
            if let file = text(statement, 0) { result.files.insert(file) }
        }
        rows(db, "SELECT model, createdAt FROM ai_code_hashes WHERE model IS NOT NULL AND model != '' ORDER BY createdAt DESC LIMIT 1", nil) { statement in
            result.model = text(statement, 0).map(Self.modelName)
            result.modelAt = Date(timeIntervalSince1970: Double(sqlite3_column_int64(statement, 1)) / 1000)
        }
        // A file Cursor's AI touched today that was also born today is one it added.
        for file in result.files {
            let birth = births[file] ?? (try? URL(fileURLWithPath: file).resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            births[file] = birth
            if birth >= start { result.created.insert(file) }
        }
        return result
    }

    private func rows(_ db: OpaquePointer, _ sql: String, _ parameter: Int64?, _ body: (OpaquePointer) -> Void) {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return }
        defer { sqlite3_finalize(statement) }
        if let parameter { sqlite3_bind_int64(statement, 1, parameter) }
        while sqlite3_step(statement) == SQLITE_ROW { body(statement) }
    }

    /// Cursor's internal names ("default" is its Auto mode, "claude-4.5-sonnet-thinking" and so on) made readable.
    static func modelName(_ raw: String) -> String {
        if raw == "default" || raw == "auto" { return "Auto" }
        if raw.hasPrefix("claude-") { return ClaudeReader.modelName(raw) }
        return raw
    }
}

private func text(_ statement: OpaquePointer, _ column: Int32) -> String? {
    guard let raw = sqlite3_column_text(statement, column) else { return nil }
    return String(cString: raw)
}
