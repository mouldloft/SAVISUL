import Foundation
import Testing
@testable import SAVISUL

@Test func timeParsesSecondsMillisecondsAndISO() {
    #expect(abs((AgentTime.parse(1_700_000_000.0)?.timeIntervalSince1970 ?? 0) - 1_700_000_000) < 0.001)
    #expect(abs((AgentTime.parse(1_700_000_000_000.0)?.timeIntervalSince1970 ?? 0) - 1_700_000_000) < 0.001)
    #expect(AgentTime.parse("2024-01-02T03:04:05Z") != nil)
    #expect(AgentTime.parse("2024-01-02T03:04:05.123Z") != nil)
    #expect(AgentTime.parse("yesterday") == nil)
    #expect(AgentTime.parse(nil) == nil)
    #expect(AgentTime.day(Date()) > 0)
}

@Test func snippetStripsMarkupAndProjectUsesTheLastComponent() {
    #expect(AgentText.snippet("<user_query>Fix the island</user_query>") == "Fix the island")
    #expect(AgentText.snippet("   \n  ") == nil)
    #expect(AgentText.project(nil) == nil)
    #expect(AgentText.project("") == nil)
    #expect(AgentText.project(NSHomeDirectory()) == nil)
    #expect(AgentText.project("/Users/me/Code/SAVISUL") == "SAVISUL")
    #expect(AgentText.snippet(String(repeating: "a", count: 200))?.hasSuffix("…") == true)
}

@Test func pricing() {
    let opus = AgentPricing.claude("claude-opus-4-6")
    let haiku = AgentPricing.claude("claude-haiku-4")
    #expect(opus.output > haiku.output)
    #expect(AgentPricing.openAI("gpt-5-mini").input < AgentPricing.openAI("gpt-5").input)
    let cost = AgentPricing.cost(AgentPricing.Rate(input: 1, output: 2, cacheRead: 0.1, cacheWrite: 1.25),
                                 input: 1_000_000, output: 1_000_000, cacheRead: 0, cacheWrite: 0)
    #expect(abs(cost - 3) < 0.001)
    #expect(AgentPricing.cost(opus, input: 0, output: 0, cacheRead: 0, cacheWrite: 0) == 0)
    // Current list prices: Opus 5.5 $4/$20 with $0.20 cache reads; Sonnet 5.x $2/$10; hour-long cache writes at 2× input.
    let current = AgentPricing.claude("claude-opus-5-5")
    #expect(current.input == 4 && current.output == 20 && abs(current.cacheRead - 0.2) < 0.0001)
    #expect(AgentPricing.claude("claude-sonnet-5-5").output == 10)
    #expect(AgentPricing.claude("claude-fable-5-1").cacheRead == 0.25)
    #expect(AgentPricing.claude("claude-opus-4-1").output == 75)
    let hour = AgentPricing.cost(current, input: 0, output: 0, cacheRead: 0, cacheWrite: 0, cacheWriteHour: 1_000_000)
    #expect(abs(hour - 8) < 0.0001)
}

@Test func modelNameAndFiveHourBlock() {
    #expect(ClaudeReader.modelName("claude-opus-4-6-20250101") == "Opus 4.6")
    #expect(ClaudeReader.modelName("claude-sonnet") == "Sonnet")
    let now = Date()
    let hour = Calendar.current.dateInterval(of: .hour, for: now)!.start
    let usage = [(date: hour.addingTimeInterval(60), tokens: 10), (date: hour.addingTimeInterval(120), tokens: 5)]
    let block = ClaudeReader.currentBlock(usage, now: hour.addingTimeInterval(180))
    #expect(block.0 == 15)
    #expect(block.1 == hour.addingTimeInterval(5 * 3600))
    let expired = ClaudeReader.currentBlock(usage, now: hour.addingTimeInterval(6 * 3600))
    #expect(expired.0 == 0)
    #expect(expired.1 == nil)
}

@Test func logTailSkipsAPartialLineAndReadsTheRest() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("savisul-log-\(UUID().uuidString).jsonl")
    try Data("{\"ok\":1}\n{broken\n{\"ok\":2}".utf8).write(to: url)
    let held = LogTail(URL(fileURLWithPath: url.path)).read()
    #expect(held.count == 2)
    #expect(AgentLog.object(held[0])?["ok"] as? Int == 1)
    #expect(AgentLog.object(held[1]) == nil)
    let handle = try FileHandle(forWritingTo: url)
    try handle.seekToEnd()
    try handle.write(contentsOf: Data("\n".utf8))
    try handle.close()
    let lines = LogTail(URL(fileURLWithPath: url.path)).read()
    #expect(lines.count == 3)
    #expect(AgentLog.object(lines[2])?["ok"] as? Int == 2)
    try? FileManager.default.removeItem(at: url)
}

@Test func claudeAndCodexShapesSurviveAMessyLine() {
    let claude = Data(#"{"type":"assistant","timestamp":"2024-01-02T03:04:05Z","cwd":"/work/SAVISUL","message":{"model":"claude-sonnet-4-5","stop_reason":"end_turn","usage":{"input_tokens":3,"output_tokens":4}}}"#.utf8)
    let object = AgentLog.object(claude)
    #expect(object?["type"] as? String == "assistant")
    #expect(AgentTime.parse(object?["timestamp"]) != nil)
    #expect(AgentLog.object(Data(#"{"type":"assistant","message":}"#.utf8)) == nil)
    let codex = Data(#"{"type":"event_msg","timestamp":"2024-01-02T03:04:05Z","payload":{"type":"task_complete","duration_ms":1500}}"#.utf8)
    #expect((AgentLog.object(codex)?["payload"] as? [String: Any])?["type"] as? String == "task_complete")
}

@Test func agentKinds() {
    #expect(AgentKind.claude.title == "Claude Code")
    #expect(AgentKind.codex.short == "Codex")
    #expect(AgentKind.mould.title == "Mould Engine Studio")
    #expect(AgentKind.allCases.count == 6)
}

@Test func mouldStudioIsReadFromItsActivityFileAndUsageLog() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("mould-reader-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder.appendingPathComponent("Usage"), withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let now = Date()
    let iso = ISO8601DateFormatter()
    let month = DateFormatter()
    month.locale = Locale(identifier: "en_US_POSIX")
    month.dateFormat = "yyyy-MM"
    // Two calls today and one two days ago, as Studio's usage log keeps them. Just after midnight the two stay today.
    let today = Calendar.current.startOfDay(for: now)
    let rows = [
        #"{"date":"\#(iso.string(from: max(today, now.addingTimeInterval(-900))))","project":"Site","model":"local:qwen2.5-1.5b","input":400,"output":100,"cost":0,"estimated":true}"#,
        #"{"date":"\#(iso.string(from: max(today, now.addingTimeInterval(-600))))","project":"Site","model":"deepseek:deepseek-v4-pro","input":1000,"output":200,"cost":0.002,"estimated":false}"#,
        #"{"date":"\#(iso.string(from: now.addingTimeInterval(-2 * 86_400)))","project":"Site","model":"deepseek:deepseek-v4-pro","input":9000,"output":900,"cost":0.02,"estimated":false}"#,
    ]
    try (rows.joined(separator: "\n") + "\n").write(to: folder.appendingPathComponent("Usage/\(month.string(from: now)).jsonl"), atomically: true, encoding: .utf8)
    func activity(working: Bool, pid: Int32 = getpid(), tokens: Int = 300, waiting: Bool = false) throws {
        let text = #"{"working":\#(working),"waiting":\#(waiting),"question":"Change index.html (1 edit)","#
            + #""model":"DeepSeek V4 Pro","modelID":"deepseek:deepseek-v4-pro","project":"Site","projectPath":"/tmp/Site","#
            + #""task":"Make a landing page","since":"\#(iso.string(from: now.addingTimeInterval(-30)))","tokens":\#(tokens),"#
            + #""updated":"\#(iso.string(from: now))","pid":\#(pid)}"#
        try text.write(to: folder.appendingPathComponent("activity.json"), atomically: true, encoding: .utf8)
    }
    let reader = MouldReader(support: folder)

    // Idle: today's calls from the log, the last one's model without its provider.
    var (status, finishes) = reader.scan(now: now, initial: true)
    #expect(status.installed && !status.working)
    #expect(status.tokensToday == 1700)
    // The week holds the call two days ago as well.
    #expect(status.tokensWeek == 11_600)
    #expect(abs((status.costToday ?? 0) - 0.002) < 0.000_001)
    #expect(status.sessionsToday == 2)
    #expect(status.model == "deepseek-v4-pro")

    // At work: the file's model, project and task, and the call in flight added to the day's tokens.
    try activity(working: true)
    (status, finishes) = reader.scan(now: now, initial: false)
    #expect(status.working)
    #expect(status.model == "DeepSeek V4 Pro")
    #expect(status.project == "Site")
    #expect(status.task == "Make a landing page")
    #expect(status.tokensToday == 2000)
    #expect(status.tokensWeek == 11_900)
    #expect(finishes.isEmpty)
    #expect(!status.waiting && status.question == nil)

    // A change waiting for the person: the island says so, with what it asks.
    try activity(working: true, waiting: true)
    (status, _) = reader.scan(now: now, initial: false)
    #expect(status.working && status.waiting)
    #expect(status.question == "Change index.html (1 edit)")

    // Done: one finish, with the project and the task.
    try activity(working: false, tokens: 0)
    (status, finishes) = reader.scan(now: now.addingTimeInterval(5), initial: false)
    #expect(!status.working)
    #expect(finishes.count == 1 && finishes.first?.kind == .mould && finishes.first?.task == "Make a landing page")

    // A Studio that quit or crashed while the file said it worked isn't at work.
    try activity(working: true, pid: 999_999)
    (status, _) = reader.scan(now: now, initial: false)
    #expect(!status.working)
}

@Test func aLogTailKeptBetweenScansSeesWhatIsWrittenLater() async throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("savisul-log-\(UUID().uuidString).jsonl")
    try Data("{\"turn\":1}\n".utf8).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    // As the agents are scanned: one tail per log, kept between scans, on a queue without a run loop, while the agent
    // goes on writing. A URL's cached size used to hide every line after the first scan.
    let seen: (first: Int, changed: Bool, later: Int) = await withCheckedContinuation { done in
        DispatchQueue(label: "test.agents").async {
            let tail = LogTail(url)
            let first = tail.read().count
            if let handle = try? FileHandle(forWritingTo: url) {
                try? handle.seekToEnd()
                try? handle.write(contentsOf: Data("{\"turn\":2}\n".utf8))
                try? handle.close()
            }
            let changed = tail.changed()
            done.resume(returning: (first, changed, tail.read().count))
        }
    }
    #expect(seen.first == 1)
    #expect(seen.changed)
    #expect(seen.later == 1)
}
