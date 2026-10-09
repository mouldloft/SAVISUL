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
    #expect(AgentKind.allCases.count == 5)
}
