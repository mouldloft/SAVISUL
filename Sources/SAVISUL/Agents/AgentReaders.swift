import AppKit
import Darwin

protocol AgentReader: AnyObject {
    var kind: AgentKind { get }
    func scan(now: Date, initial: Bool) -> (AgentStatus, [AgentFinish])
}

private let home = FileManager.default.homeDirectoryForCurrentUser

enum AgentLog {
    static func object(_ line: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: line)) as? [String: Any]
    }
}

private func json(_ line: Data) -> [String: Any]? { AgentLog.object(line) }

private func head(_ line: Data, _ count: Int = 360) -> String {
    String(decoding: line.prefix(count), as: UTF8.self)
}

private func recentFiles(in folder: URL, depth: Int, ext: String, within: TimeInterval, now: Date) -> [URL] {
    var result: [URL] = []
    func walk(_ url: URL, _ level: Int) {
        guard let items = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
                                                                       options: [.skipsHiddenFiles]) else { return }
        for item in items {
            let values = try? item.resourceValues(forKeys: [.contentModificationDateKey, .isDirectoryKey])
            if values?.isDirectory == true {
                // A folder's date only moves when an entry is added to it directly, not when a file inside grows,
                // so a dated folder ("2026", a long-lived project) can be old while its logs are live.
                if level < depth { walk(item, level + 1) }
            } else if item.pathExtension == ext, now.timeIntervalSince(values?.contentModificationDate ?? .distantPast) < within {
                result.append(item)
            }
        }
    }
    walk(folder, 0)
    return result
}

/// Which agent programs are running, by process name. Cheap enough for every scan.
enum AgentProcesses {
    static func running(_ names: Set<String>) -> Bool {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return true }
        var pids = [pid_t](repeating: 0, count: Int(count) + 64)
        let filled = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard filled > 0 else { return true }
        var name = [CChar](repeating: 0, count: 64)
        for pid in pids.prefix(Int(filled)) where pid > 0 {
            if proc_name(pid, &name, UInt32(name.count)) > 0, names.contains(String(cString: name)) { return true }
        }
        return false
    }
}

// MARK: - Codex

final class CodexReader: AgentReader {
    let kind = AgentKind.codex
    private let root = home.appendingPathComponent(".codex/sessions")

    private struct Session {
        var id = ""
        var sub = false
        var cwd: String?
        var model: String?
        var openTurn: String?
        var started: Date?
        var last = Date.distantPast
        var lastTotal = -1
        var prompt: String?
        var originator: String?
    }

    private struct Limits {
        var stamp = Date.distantPast
        var windows: [(minutes: Int, used: Double, resets: Date?)] = []
        var plan: String?
    }

    private var tails: [String: LogTail] = [:]
    private var sessions: [String: Session] = [:]
    private var tokens: [Int: Int] = [:]
    private var cached: [Int: Int] = [:]
    private var cost: [Int: Double] = [:]
    private var code: [Int: CodeTally] = [:]
    private var surfaceDays: [Int: [AgentSurface: SurfaceUsage]] = [:]
    private var patches: Set<String> = []
    private var activeDays: [Int: Set<String>] = [:]
    private var limits = Limits()
    private var blocked: Date?
    private static let patchMark = Data("Begin Patch".utf8)

    func scan(now: Date, initial: Bool) -> (AgentStatus, [AgentFinish]) {
        var status = AgentStatus(kind: kind)
        status.installed = FileManager.default.fileExists(atPath: home.appendingPathComponent(".codex").path)
        guard status.installed else { return (status, []) }
        var finishes: [AgentFinish] = []
        for url in recentFiles(in: root, depth: 3, ext: "jsonl", within: 86_400 * 7, now: now) {
            let tail = tails[url.path] ?? LogTail(url)
            tails[url.path] = tail
            guard tail.changed() else { continue }
            var session = sessions[url.path] ?? Session()
            tail.forEachLine { line in
                if let finish = handle(line, &session, now: now, initial: initial) { finishes.append(finish) }
            }
            sessions[url.path] = session
        }

        let today = AgentTime.day(now)
        status.tokensToday = tokens[today] ?? 0
        status.cacheToday = cached[today] ?? 0
        status.code = code[today] ?? CodeTally()
        status.surfaces = surfaceDays[today] ?? [:]
        status.tokensWeek = AgentWeek.days(now).reduce(0) { $0 + (tokens[$1] ?? 0) }
        status.codeWeek = AgentWeek.code(code, now: now)
        status.surfacesWeek = AgentWeek.surfaces(surfaceDays, now: now)
        status.costToday = status.tokensToday > 0 ? cost[today] : nil
        status.sessionsToday = activeDays[today]?.count ?? 0
        let roots = sessions.values.filter { !$0.sub }
        // A turn left open by a closed app or a killed CLI isn't work.
        let alive = AgentProcesses.running(["codex"]) || !NSRunningApplication.runningApplications(withBundleIdentifier: "com.openai.codex").isEmpty
        let working = roots.filter { $0.openTurn != nil && now.timeIntervalSince($0.last) < 600 && alive }
        status.working = !working.isEmpty
        status.runs = working.count
        let focus = working.max { ($0.started ?? .distantPast) < ($1.started ?? .distantPast) }
            ?? roots.max { $0.last < $1.last }
        status.since = focus?.openTurn != nil ? focus?.started : nil
        status.project = AgentText.project(focus?.cwd)
        status.projectPath = focus?.cwd
        status.model = focus?.model
        status.task = focus?.openTurn != nil ? focus?.prompt : nil
        status.surface = focus.map(Self.surface)
        status.lastActive = sessions.values.map(\.last).max()
        status.plan = limits.plan.map { $0.capitalized }
        status.limits = limits.windows.map { window in
            let expired = window.resets.map { $0 < now } ?? false
            return AgentLimit(window: .minutes(window.minutes), used: expired ? 0 : window.used / 100,
                              resets: expired ? nil : window.resets)
        }
        let exhausted = limits.windows.filter { ($0.resets ?? .distantPast) > now && $0.used >= 99.5 }
        if let blocked, blocked > now.addingTimeInterval(-3600 * 6), !exhausted.isEmpty || now.timeIntervalSince(blocked) < 1800 {
            status.limitHit = true
            status.limitUntil = exhausted.compactMap(\.resets).max()
        }
        return (status, finishes)
    }

    /// The Codex app reports itself as the originator; the VS Code extension says so too.
    private static func surface(_ session: Session) -> AgentSurface {
        let origin = (session.originator ?? "").lowercased()
        if origin.contains("vscode") { return EditorWorkspaces.shared.surface(for: session.cwd, fallback: .vscode) }
        if origin.contains("desktop") || origin.contains("app") { return .desktop }
        return .terminal
    }

    private func handle(_ line: Data, _ session: inout Session, now: Date, initial: Bool) -> AgentFinish? {
        let prefix = head(line)
        let interesting = prefix.contains("\"event_msg\"") || prefix.contains("\"turn_context\"") || prefix.contains("\"session_meta\"")
        // Patches ride inside tool calls; reviewer transcripts repeat old history as messages, so only calls count.
        let patch = prefix.contains("\"response_item\"") && line.range(of: Self.patchMark) != nil
        guard interesting || patch, let object = json(line), let payload = object["payload"] as? [String: Any] else { return nil }
        let stamp = AgentTime.parse(object["timestamp"]) ?? now
        session.last = max(session.last, stamp)
        if patch {
            countPatch(payload, session: session, stamp: stamp)
            return nil
        }
        switch object["type"] as? String {
        case "session_meta":
            session.id = payload["id"] as? String ?? session.id
            session.cwd = payload["cwd"] as? String ?? session.cwd
            session.originator = payload["originator"] as? String ?? session.originator
            if let source = payload["source"] as? [String: Any], source["subagent"] != nil { session.sub = true }
            if payload["parent_thread_id"] is String { session.sub = true }
        case "turn_context":
            session.model = payload["model"] as? String ?? session.model
            session.cwd = payload["cwd"] as? String ?? session.cwd
        case "event_msg":
            switch payload["type"] as? String {
            case "task_started":
                session.openTurn = payload["turn_id"] as? String ?? "turn"
                session.started = AgentTime.parse(payload["started_at"]) ?? stamp
                activeDays[AgentTime.day(stamp), default: []].insert(session.id)
            case "user_message":
                if let text = payload["message"] as? String, let snippet = AgentText.snippet(text) { session.prompt = snippet }
            case "task_complete":
                let started = AgentTime.parse(payload["started_at"]) ?? session.started
                let duration = (payload["duration_ms"] as? Double).map { $0 / 1000 } ?? started.map { stamp.timeIntervalSince($0) } ?? 0
                var errorText: String?
                var limitHit = false
                if let error = payload["error"] as? [String: Any] {
                    errorText = (error["message"] as? String).map { String($0.prefix(120)) }
                    if (error["codex_error_info"] as? String)?.contains("usage_limit") == true {
                        limitHit = true
                        blocked = stamp
                    }
                }
                let wasOpen = session.openTurn != nil
                session.openTurn = nil
                if wasOpen, !initial, !session.sub {
                    return AgentFinish(kind: kind, project: AgentText.project(session.cwd), duration: duration,
                                       limitHit: limitHit, error: errorText, task: session.prompt)
                }
            case "turn_aborted":
                session.openTurn = nil
            case "token_count":
                if let info = payload["info"] as? [String: Any],
                   let total = (info["total_token_usage"] as? [String: Any])?["total_tokens"] as? Int, total != session.lastTotal {
                    session.lastTotal = total
                    if let last = info["last_token_usage"] as? [String: Any] {
                        let day = AgentTime.day(stamp)
                        let input = last["input_tokens"] as? Int ?? 0
                        let cachedInput = min(last["cached_input_tokens"] as? Int ?? 0, input)
                        let write = last["cache_write_input_tokens"] as? Int ?? 0
                        let output = last["output_tokens"] as? Int ?? 0
                        // Input includes the cached part; count it apart like Claude's cache reads.
                        let fresh = input - cachedInput + output
                        tokens[day, default: 0] += fresh
                        cached[day, default: 0] += cachedInput
                        let rate = AgentPricing.openAI(session.model ?? "gpt-5")
                        cost[day, default: 0] += AgentPricing.cost(rate, input: max(input - cachedInput - write, 0), output: output, cacheRead: cachedInput, cacheWrite: write)
                        surfaceDays[day, default: [:]][Self.surface(session), default: SurfaceUsage()]
                            .add(SurfaceUsage(tokens: fresh, cache: cachedInput, model: session.model, last: stamp))
                    }
                }
                if let rates = payload["rate_limits"] as? [String: Any], stamp >= limits.stamp {
                    var next = Limits(stamp: stamp, windows: [], plan: rates["plan_type"] as? String ?? limits.plan)
                    for key in ["primary", "secondary"] {
                        guard let window = rates[key] as? [String: Any] else { continue }
                        next.windows.append((window["window_minutes"] as? Int ?? 0, window["used_percent"] as? Double ?? 0,
                                             AgentTime.parse(window["resets_at"])))
                    }
                    if !next.windows.isEmpty { limits = next }
                }
            default:
                break
            }
        default:
            break
        }
        return nil
    }


    private func countPatch(_ payload: [String: Any], session: Session, stamp: Date) {
        let kind = payload["type"] as? String
        guard kind == "custom_tool_call" || kind == "function_call" else { return }
        let id = payload["call_id"] as? String ?? payload["id"] as? String ?? "\(stamp.timeIntervalSince1970)"
        guard patches.insert(id).inserted else { return }
        var text = payload["input"] as? String ?? payload["arguments"] as? String ?? ""
        guard let begin = text.range(of: "*** Begin Patch") else { return }
        text = String(text[begin.lowerBound...])
        if let end = text.range(of: "*** End Patch") { text = String(text[..<end.upperBound]) }
        // Patches passed through a script arrive as a string literal with escaped newlines.
        if !text.contains("\n"), text.contains("\\n") {
            text = text.replacingOccurrences(of: "\\n", with: "\n").replacingOccurrences(of: "\\t", with: "\t")
                .replacingOccurrences(of: "\\\"", with: "\"")
        }
        var tally = CodeTally()
        tally.addPatch(text, within: session.cwd)
        guard !tally.isEmpty else { return }
        let day = AgentTime.day(stamp)
        code[day, default: CodeTally()].add(tally)
        surfaceDays[day, default: [:]][Self.surface(session), default: SurfaceUsage()].code.add(tally)
    }
}

// MARK: - Claude Code

final class ClaudeReader: AgentReader {
    let kind = AgentKind.claude

    private var roots: [URL] {
        var list = [home.appendingPathComponent(".claude/projects"), home.appendingPathComponent(".config/claude/projects")]
        if let custom = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"] {
            list.insert(URL(fileURLWithPath: custom).appendingPathComponent("projects"), at: 0)
        }
        return list
    }

    private struct Session {
        var cwd: String?
        /// Where the session started: the project. The shell can wander into subfolders; the project stays.
        var root: String?
        var model: String?
        var working = false
        var runStart: Date?
        var last = Date.distantPast
        var prompt: String?
        var entrypoint: String?
    }

    private struct DayUsage {
        var fresh = 0
        var cache = 0
        var cost = 0.0
    }

    private var tails: [String: LogTail] = [:]
    private var sessions: [String: Session] = [:]
    private var seen: Set<String> = []
    private var seenResults: Set<String> = []
    private var usage: [(date: Date, tokens: Int)] = []
    private var days: [Int: DayUsage] = [:]
    private var code: [Int: CodeTally] = [:]
    private var surfaceDays: [Int: [AgentSurface: SurfaceUsage]] = [:]
    private var activeDays: [Int: Set<String>] = [:]
    private var blockedUntil: Date?

    private static let assistantMark = Data(#""type":"assistant""#.utf8)
    private static let userMark = Data(#""type":"user""#.utf8)

    func scan(now: Date, initial: Bool) -> (AgentStatus, [AgentFinish]) {
        var status = AgentStatus(kind: kind)
        let installed = roots.contains { FileManager.default.fileExists(atPath: $0.deletingLastPathComponent().path) }
            || FileManager.default.fileExists(atPath: home.appendingPathComponent(".local/bin/claude").path)
        status.installed = installed
        guard installed else { return (status, []) }
        var finishes: [AgentFinish] = []
        for root in roots {
            for url in recentFiles(in: root, depth: 3, ext: "jsonl", within: 86_400 * 8, now: now) {
                let tail = tails[url.path] ?? LogTail(url)
                tails[url.path] = tail
                guard tail.changed() else { continue }
                var session = sessions[url.path] ?? Session()
                tail.forEachLine { line in
                    // Most of a session log is tool output; only parse what can carry a turn, a reply or usage.
                    guard line.range(of: Self.assistantMark) != nil || line.range(of: Self.userMark) != nil else { return }
                    if let finish = handle(line, &session, file: url.path, now: now, initial: initial) { finishes.append(finish) }
                }
                sessions[url.path] = session
            }
        }
        let today = AgentTime.day(now)
        let day = days[today] ?? DayUsage()
        status.tokensToday = day.fresh
        status.cacheToday = day.cache
        status.costToday = day.fresh > 0 ? day.cost : nil
        status.code = code[today] ?? CodeTally()
        status.surfaces = surfaceDays[today] ?? [:]
        status.tokensWeek = AgentWeek.days(now).reduce(0) { $0 + (days[$1]?.fresh ?? 0) }
        status.codeWeek = AgentWeek.code(code, now: now)
        status.surfacesWeek = AgentWeek.surfaces(surfaceDays, now: now)
        status.sessionsToday = activeDays[today]?.count ?? 0
        // The terminal CLI and the VS Code/Cursor extension both run a process named "claude"; with none left,
        // a turn whose end never reached the log (window closed mid-answer) isn't work either.
        let alive = AgentProcesses.running(["claude"])
        let working = sessions.values.filter { $0.working && now.timeIntervalSince($0.last) < 600 && alive }
        status.working = !working.isEmpty
        status.runs = working.count
        let focus = working.max { ($0.runStart ?? .distantPast) < ($1.runStart ?? .distantPast) } ?? sessions.values.max { $0.last < $1.last }
        status.since = status.working ? focus?.runStart : nil
        status.project = AgentText.project(focus?.root ?? focus?.cwd)
        status.projectPath = focus?.root ?? focus?.cwd
        status.model = focus?.model.map(Self.modelName)
        status.task = status.working ? focus?.prompt : nil
        status.surface = focus.map { Self.surface($0) }
        status.lastActive = sessions.values.map(\.last).max()

        usage.removeAll { now.timeIntervalSince($0.date) > 86_400 * 8 }
        let (blockTokens, blockEnd) = Self.currentBlock(usage, now: now)
        var limits: [AgentLimit] = []
        if let blockEnd {
            limits.append(AgentLimit(window: .minutes(300), used: nil, resets: blockEnd, tokens: blockTokens))
        }
        let week = usage.filter { now.timeIntervalSince($0.date) < 86_400 * 7 }.reduce(0) { $0 + $1.tokens }
        if week > 0 {
            limits.append(AgentLimit(window: .days(7), used: nil, resets: nil, tokens: week))
        }
        status.limits = limits
        if let blockedUntil, blockedUntil > now {
            status.limitHit = true
            status.limitUntil = blockedUntil
        }
        return (status, finishes)
    }

    /// The Claude Code extension runs in both VS Code and Cursor; the folder tells them apart.
    private static func surface(_ session: Session) -> AgentSurface {
        switch session.entrypoint {
        case "claude-vscode": EditorWorkspaces.shared.surface(for: session.root ?? session.cwd, fallback: .vscode)
        case let value? where value.hasPrefix("sdk") || value.contains("desktop"): .desktop
        default: .terminal
        }
    }

    private func handle(_ line: Data, _ session: inout Session, file: String, now: Date, initial: Bool) -> AgentFinish? {
        guard let object = json(line) else { return nil }
        let type = object["type"] as? String
        guard type == "user" || type == "assistant" else { return nil }
        let stamp = AgentTime.parse(object["timestamp"]) ?? now
        session.last = max(session.last, stamp)
        session.cwd = object["cwd"] as? String ?? session.cwd
        if session.root == nil { session.root = session.cwd }
        session.entrypoint = object["entrypoint"] as? String ?? session.entrypoint
        let sidechain = object["isSidechain"] as? Bool ?? false
        let message = object["message"] as? [String: Any] ?? [:]
        let dayKey = AgentTime.day(stamp)
        activeDays[dayKey, default: []].insert(file)

        if type == "assistant" {
            if let model = message["model"] as? String, !model.hasPrefix("<") { session.model = model }
            if let usage = message["usage"] as? [String: Any] {
                // Claude Code writes one line per content block with the same usage; count each reply once.
                let key = "\(message["id"] as? String ?? "")|\(object["requestId"] as? String ?? "")"
                if key == "|" || !seen.contains(key) {
                    seen.insert(key)
                    let input = usage["input_tokens"] as? Int ?? 0
                    let output = usage["output_tokens"] as? Int ?? 0
                    let read = usage["cache_read_input_tokens"] as? Int ?? 0
                    let write = usage["cache_creation_input_tokens"] as? Int ?? 0
                    let fresh = input + output + write
                    let model = message["model"] as? String ?? "claude-sonnet"
                    // Claude Code writes its cache for an hour, which costs 2× input instead of 1.25×; the log says how much went where.
                    let split = usage["cache_creation"] as? [String: Any]
                    let hourWrite = min(split?["ephemeral_1h_input_tokens"] as? Int ?? 0, write)
                    let spent = AgentPricing.cost(AgentPricing.claude(model), input: input, output: output, cacheRead: read,
                                                  cacheWrite: write - hourWrite, cacheWriteHour: hourWrite)
                    days[dayKey, default: DayUsage()].fresh += fresh
                    days[dayKey, default: DayUsage()].cache += read
                    days[dayKey, default: DayUsage()].cost += spent
                    var slice = SurfaceUsage(tokens: fresh, cache: read, model: Self.modelName(model), last: stamp)
                    slice.code = CodeTally()
                    surfaceDays[dayKey, default: [:]][Self.surface(session), default: SurfaceUsage()].add(slice)
                    self.usage.append((stamp, fresh))
                }
            }
            if let content = message["content"] as? [[String: Any]] {
                for block in content {
                    if let text = block["text"] as? String, let reset = Self.limitReset(in: text) {
                        blockedUntil = reset
                    }
                }
            }
            guard !sidechain else { return nil }
            let stop = message["stop_reason"] as? String
            if stop == "end_turn" || stop == "stop_sequence" || stop == "max_tokens" || stop == "refusal" {
                let wasWorking = session.working
                session.working = false
                if wasWorking, !initial, let start = session.runStart {
                    session.runStart = nil
                    return AgentFinish(kind: kind, project: AgentText.project(session.root ?? session.cwd), duration: stamp.timeIntervalSince(start), error: nil, task: session.prompt)
                }
                session.runStart = nil
            } else {
                session.working = true
                session.runStart = session.runStart ?? stamp
            }
            return nil
        }

        countCode(object, session: session, day: dayKey, stamp: stamp)
        // A compacted conversation restarts with a summary written as a user message; it isn't a new task.
        guard !sidechain, object["isCompactSummary"] as? Bool != true, object["isMeta"] as? Bool != true else { return nil }
        var prompt: String?
        var toolResult = false
        if let text = message["content"] as? String {
            prompt = text
        } else if let content = message["content"] as? [[String: Any]] {
            for block in content {
                if block["type"] as? String == "tool_result" { toolResult = true }
                // Pasted images arrive as "[Image: …]" placeholders next to what the person actually wrote.
                if block["type"] as? String == "text", let text = block["text"] as? String, prompt == nil || !text.hasPrefix("[Image") {
                    prompt = text
                }
            }
        }
        // Background-task notices land in the log as user messages, sometimes hours after the turn ended, and often
        // nothing answers them. They are neither the task nor a sign of work: only the reply that follows counts.
        let origin = (object["origin"] as? [String: Any])?["kind"] as? String
        if object["promptSource"] as? String == "system" || (origin != nil && origin != "human")
            || prompt?.hasPrefix("<task-notification") == true || prompt?.hasPrefix("<system-reminder") == true {
            return nil
        }
        if prompt?.hasPrefix("[Image") == true { prompt = nil; toolResult = true }
        if let prompt, prompt.hasPrefix("[Request interrupted") {
            session.working = false
            session.runStart = nil
            return nil
        }
        if toolResult {
            session.working = true
            session.runStart = session.runStart ?? stamp
        } else if let prompt, !prompt.hasPrefix("<command-"), !prompt.hasPrefix("<local-command"), !prompt.hasPrefix("Caveat:") {
            session.working = true
            session.runStart = stamp
            session.prompt = AgentText.snippet(prompt)
        }
        return nil
    }

    /// File edits come back as tool results with an exact patch; new files arrive as `create` with their content.
    private func countCode(_ object: [String: Any], session: Session, day: Int, stamp: Date) {
        guard let result = object["toolUseResult"] as? [String: Any], let path = result["filePath"] as? String,
              CodeTally.inside(path, session.root ?? session.cwd) else { return }
        let id = object["uuid"] as? String ?? "\(path)|\(stamp.timeIntervalSince1970)"
        guard seenResults.insert(id).inserted else { return }
        var tally = CodeTally()
        if result["type"] as? String == "create", let content = result["content"] as? String {
            tally.created.insert(path)
            tally.added = content.isEmpty ? 0 : content.split(separator: "\n", omittingEmptySubsequences: false).count
        } else if let hunks = result["structuredPatch"] as? [[String: Any]], !hunks.isEmpty {
            tally.edited.insert(path)
            for hunk in hunks {
                for line in hunk["lines"] as? [String] ?? [] {
                    if line.hasPrefix("+") { tally.added += 1 } else if line.hasPrefix("-") { tally.removed += 1 }
                }
            }
        } else {
            return
        }
        code[day, default: CodeTally()].add(tally)
        surfaceDays[day, default: [:]][Self.surface(session), default: SurfaceUsage()].code.add(tally)
    }

    /// Claude bills in five-hour windows that start at the hour of the first message.
    static func currentBlock(_ usage: [(date: Date, tokens: Int)], now: Date) -> (Int, Date?) {
        var start: Date?
        var end: Date?
        var tokens = 0
        for entry in usage.sorted(by: { $0.date < $1.date }) {
            if end == nil || entry.date >= end! {
                let hour = Calendar.current.dateInterval(of: .hour, for: entry.date)?.start ?? entry.date
                start = hour
                end = hour.addingTimeInterval(5 * 3600)
                tokens = 0
            }
            tokens += entry.tokens
        }
        guard start != nil, let end, end > now else { return (0, nil) }
        return (tokens, end)
    }

    /// "usage limit reached|1710000000" → the moment the limit lifts.
    static func limitReset(in text: String) -> Date? {
        guard text.contains("usage limit reached|"),
              let raw = text.split(separator: "|").last,
              let epoch = Double(raw.trimmingCharacters(in: .whitespaces)) else { return nil }
        return Date(timeIntervalSince1970: epoch)
    }

    static func modelName(_ raw: String) -> String {
        var name = raw.replacingOccurrences(of: "claude-", with: "")
        if let range = name.range(of: #"-\d{8}$"#, options: .regularExpression) { name.removeSubrange(range) }
        let parts = name.split(separator: "-").map(String.init)
        guard let family = parts.first else { return raw }
        let version = parts.dropFirst().joined(separator: ".")
        return family.capitalized + (version.isEmpty ? "" : " " + version)
    }
}

// MARK: - OpenCode

final class OpenCodeReader: AgentReader {
    let kind = AgentKind.opencode
    private let root = home.appendingPathComponent(".local/share/opencode/storage/message")

    private struct Message {
        var session: String
        var role: String
        var created: Date
        var completed: Date?
        var tokens: Int
        var cost: Double
        var model: String?
        var cwd: String?
    }

    private var messages: [String: Message] = [:]
    private var stamps: [String: Date] = [:]
    private var reported: Set<String> = []

    func scan(now: Date, initial: Bool) -> (AgentStatus, [AgentFinish]) {
        var status = AgentStatus(kind: kind)
        status.installed = FileManager.default.fileExists(atPath: home.appendingPathComponent(".local/share/opencode").path)
            || FileManager.default.fileExists(atPath: home.appendingPathComponent(".config/opencode").path)
        guard status.installed else { return (status, []) }
        var finishes: [AgentFinish] = []
        for url in recentFiles(in: root, depth: 1, ext: "json", within: 86_400 * 2, now: now) {
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? now
            guard stamps[url.path] != modified, let data = try? Data(contentsOf: url), let object = json(data) else { continue }
            stamps[url.path] = modified
            let time = object["time"] as? [String: Any] ?? [:]
            let tokens = object["tokens"] as? [String: Any] ?? [:]
            let cache = tokens["cache"] as? [String: Any] ?? [:]
            func count(_ dictionary: [String: Any], _ key: String) -> Int { dictionary[key] as? Int ?? 0 }
            let total: Int = count(tokens, "input") + count(tokens, "output") + count(tokens, "reasoning") + count(cache, "write")
            let id = object["id"] as? String ?? url.path
            let message = Message(session: object["sessionID"] as? String ?? "", role: object["role"] as? String ?? "",
                                  created: AgentTime.parse(time["created"]) ?? modified, completed: AgentTime.parse(time["completed"]),
                                  tokens: total, cost: object["cost"] as? Double ?? 0, model: object["modelID"] as? String,
                                  cwd: (object["path"] as? [String: Any])?["cwd"] as? String)
            messages[id] = message
            if message.role == "assistant", let completed = message.completed, !reported.contains(id) {
                reported.insert(id)
                let start = messages.values.filter { $0.session == message.session && $0.role == "user" && $0.created <= message.created }
                    .map(\.created).max() ?? message.created
                if !initial { finishes.append(AgentFinish(kind: kind, project: AgentText.project(message.cwd), duration: completed.timeIntervalSince(start), error: nil, task: nil)) }
            }
        }
        let today = AgentTime.day(now)
        let todays = messages.values.filter { AgentTime.day($0.created) == today }
        status.tokensToday = todays.reduce(0) { $0 + $1.tokens }
        let spent = todays.reduce(0) { $0 + $1.cost }
        status.costToday = spent > 0 ? spent : nil
        status.sessionsToday = Set(todays.map(\.session)).count
        let open = messages.values.filter { $0.role == "assistant" && $0.completed == nil && now.timeIntervalSince($0.created) < 900 }
        status.working = !open.isEmpty
        status.runs = Set(open.map(\.session)).count
        let latest = messages.values.filter { $0.role == "assistant" }.max { $0.created < $1.created }
        status.since = open.map(\.created).min()
        status.project = AgentText.project(latest?.cwd)
        status.projectPath = latest?.cwd
        status.model = latest?.model
        status.lastActive = messages.values.map { $0.completed ?? $0.created }.max()
        return (status, finishes.filter { $0.duration > 0 })
    }
}

// MARK: - Copilot CLI

final class CopilotReader: AgentReader {
    let kind = AgentKind.copilot
    private let folders = [home.appendingPathComponent(".copilot/session-state"), home.appendingPathComponent(".copilot/history-session-state")]
    private var tails: [String: LogTail] = [:]
    private var activeSince: [String: Date] = [:]
    private var lastWrite: [String: Date] = [:]
    private var model: String?
    private var project: String?
    private var tokens: [Int: Int] = [:]
    private let tokenPattern = try! NSRegularExpression(pattern: #""(?:input|output|prompt|completion)_?[tT]okens"\s*:\s*(\d+)"#)
    private let modelPattern = try! NSRegularExpression(pattern: #""model"\s*:\s*"([^"]{2,60})""#)
    private let cwdPattern = try! NSRegularExpression(pattern: #""(?:cwd|workingDirectory)"\s*:\s*"([^"]{2,300})""#)

    func scan(now: Date, initial: Bool) -> (AgentStatus, [AgentFinish]) {
        var status = AgentStatus(kind: kind)
        status.installed = FileManager.default.fileExists(atPath: home.appendingPathComponent(".copilot").path)
        guard status.installed else { return (status, []) }
        var finishes: [AgentFinish] = []
        for folder in folders {
            for ext in ["jsonl", "json"] {
                for url in recentFiles(in: folder, depth: 1, ext: ext, within: 86_400 * 2, now: now) {
                    let tail = tails[url.path] ?? LogTail(url)
                    tails[url.path] = tail
                    guard tail.changed() else { continue }
                    let lines = tail.read(limit: 4 << 20)
                    guard !lines.isEmpty else { continue }
                    let modified = tail.modified
                    if !initial, now.timeIntervalSince(modified) < 60 { activeSince[url.path] = activeSince[url.path] ?? modified }
                    lastWrite[url.path] = modified
                    for line in lines { read(String(decoding: line, as: UTF8.self), stamp: modified) }
                }
            }
        }
        for (path, since) in activeSince {
            let last = lastWrite[path] ?? since
            if now.timeIntervalSince(last) > 75 {
                activeSince[path] = nil
                finishes.append(AgentFinish(kind: kind, project: project, duration: last.timeIntervalSince(since), error: nil, task: nil))
            }
        }
        status.working = !activeSince.isEmpty
        status.runs = activeSince.count
        status.since = activeSince.values.min()
        status.model = model
        status.project = AgentText.project(project)
        status.projectPath = project
        status.tokensToday = tokens[AgentTime.day(now)] ?? 0
        status.lastActive = lastWrite.values.max()
        status.sessionsToday = lastWrite.values.filter { AgentTime.day($0) == AgentTime.day(now) }.count
        return (status, finishes)
    }

    private func read(_ text: String, stamp: Date) {
        let range = NSRange(text.startIndex..., in: text)
        for match in tokenPattern.matches(in: text, range: range) {
            if let value = Range(match.range(at: 1), in: text), let count = Int(text[value]) { tokens[AgentTime.day(stamp), default: 0] += count }
        }
        if let match = modelPattern.firstMatch(in: text, range: range), let value = Range(match.range(at: 1), in: text) { model = String(text[value]) }
        if let match = cwdPattern.firstMatch(in: text, range: range), let value = Range(match.range(at: 1), in: text) { project = String(text[value]) }
    }
}

// MARK: - Cursor

final class CursorReader: AgentReader {
    let kind = AgentKind.cursor
    private let root = home.appendingPathComponent(".cursor/projects")

    private struct Transcript {
        var project: String?
        var path: String?
        var working = false
        /// The transcript ends on the person's prompt: Cursor is thinking before it writes anything.
        var awaiting = false
        var runStart: Date?
        var last = Date.distantPast
        var prompt: String?
    }

    private var tails: [String: LogTail] = [:]
    private var transcripts: [String: Transcript] = [:]
    private var names: [String: String] = [:]

    func scan(now: Date, initial: Bool) -> (AgentStatus, [AgentFinish]) {
        var status = AgentStatus(kind: kind)
        status.installed = FileManager.default.fileExists(atPath: home.appendingPathComponent(".cursor").path)
        guard status.installed else { return (status, []) }
        var finishes: [AgentFinish] = []
        let running = !NSRunningApplication.runningApplications(withBundleIdentifier: "com.todesktop.230313mzl4w4u92").isEmpty
        let projects = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for project in projects {
            let folder = project.appendingPathComponent("agent-transcripts")
            for url in recentFiles(in: folder, depth: 1, ext: "jsonl", within: 86_400 * 2, now: now) {
                let tail = tails[url.path] ?? LogTail(url)
                tails[url.path] = tail
                guard tail.changed() else { continue }
                guard let text = tail.tail() else { continue }
                var transcript = transcripts[url.path] ?? Transcript()
                if transcript.path == nil {
                    transcript.path = path(for: project.lastPathComponent)
                    transcript.project = transcript.path.map { ($0 as NSString).lastPathComponent }
                }
                let modified = tail.modified
                let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
                let last = lines.last.map(String.init) ?? ""
                if let query = lines.last(where: { $0.contains("\"role\":\"user\"") && $0.contains("user_query") }) {
                    transcript.prompt = AgentText.snippet(String(query).replacingOccurrences(of: "\\n", with: " "))
                }
                if last.contains("\"turn_ended\"") {
                    if transcript.working, !initial, let start = transcript.runStart {
                        finishes.append(AgentFinish(kind: kind, project: transcript.project, duration: modified.timeIntervalSince(start), error: nil, task: transcript.prompt))
                    }
                    transcript.working = false
                    transcript.awaiting = false
                    transcript.runStart = nil
                } else if last.contains("\"role\":\"user\"") {
                    transcript.working = true
                    transcript.awaiting = true
                    transcript.runStart = modified
                } else {
                    // Tool calls and replies are written as the turn goes; the turn ends with "turn_ended".
                    transcript.working = true
                    transcript.awaiting = false
                    transcript.runStart = transcript.runStart ?? modified
                }
                transcript.last = modified
                transcripts[url.path] = transcript
            }
        }
        // A turn that never wrote "turn_ended" (stopped, crashed, Cursor closed) goes quiet. Checked on every scan,
        // not only when the file changes, so a silent transcript stops counting as work instead of lingering for hours.
        for (path, transcript) in transcripts where transcript.working
            && (!running || now.timeIntervalSince(transcript.last) > (transcript.awaiting ? 900 : 600)) {
            transcripts[path]?.working = false
            transcripts[path]?.awaiting = false
            transcripts[path]?.runStart = nil
        }
        let working = transcripts.values.filter(\.working)
        status.working = !working.isEmpty
        status.runs = working.count
        let focus = working.max { $0.last < $1.last } ?? transcripts.values.max { $0.last < $1.last }
        status.since = status.working ? focus?.runStart : nil
        status.project = focus?.project
        status.projectPath = focus?.path
        status.task = status.working ? focus?.prompt : nil
        status.lastActive = transcripts.values.map(\.last).max()
        status.sessionsToday = transcripts.values.filter { AgentTime.day($0.last) == AgentTime.day(now) }.count
        status.surface = .cursor
        // Cursor keeps no token counts on disk, but it records every line its AI writes and with which model.
        let tracking = CursorTracking.shared.today(now: now)
        status.model = tracking.model
        var code = CodeTally()
        code.added = tracking.lines
        code.created = tracking.created
        code.edited = tracking.files
        status.code = code
        if !code.isEmpty || tracking.model != nil {
            status.surfaces[.cursor] = SurfaceUsage(code: code, model: tracking.model, last: tracking.modelAt ?? status.lastActive ?? .distantPast)
        }
        let week = CursorTracking.shared.week(now: now)
        var weekCode = CodeTally()
        weekCode.added = week.lines
        weekCode.created = week.created
        weekCode.edited = week.files
        status.codeWeek = weekCode
        if !weekCode.isEmpty { status.surfacesWeek[.cursor] = SurfaceUsage(code: weekCode, model: tracking.model, last: tracking.modelAt ?? .distantPast) }
        return (status, finishes)
    }

    /// Cursor encodes a project path by replacing slashes with dashes; walk the disk to undo it.
    private func path(for encoded: String) -> String {
        if let cached = names[encoded] { return cached }
        let tokens = encoded.split(separator: "-").map(String.init)
        var path = "/"
        var index = 0
        while index < tokens.count {
            var matched = false
            for end in stride(from: tokens.count, to: index, by: -1) {
                let slice = tokens[index..<end]
                for joiner in ["-", " ", ".", "_"] {
                    let candidate = (path as NSString).appendingPathComponent(slice.joined(separator: joiner))
                    if FileManager.default.fileExists(atPath: candidate) {
                        path = candidate
                        index = end
                        matched = true
                        break
                    }
                }
                if matched { break }
            }
            if !matched {
                path = (path as NSString).appendingPathComponent(tokens[index...].joined(separator: "-"))
                break
            }
        }
        names[encoded] = path
        return path
    }
}
