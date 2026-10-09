import Foundation
import Testing
@testable import SAVISUL

@Test func lyricsParseTimesAndPickTheLineBeingSung() {
    let lines = Lyrics.parse("[00:01.50] one\n[00:05] two\n[1:00.2] three\n[00:00] intro")
    #expect(lines.map(\.text) == ["intro", "one", "two", "three"])
    #expect(abs(lines[1].time - 1.5) < 0.001)
    #expect(abs(lines[3].time - 60.2) < 0.001)
    let early = Lyrics.sung(lines, at: 0)
    #expect(early.current == "intro")
    #expect(early.next == "one")
    let mid = Lyrics.sung(lines, at: 3)
    #expect(mid.current == "one")
    #expect(mid.next == "two")
    #expect(mid.progress > 0 && mid.progress < 1)
    #expect(Lyrics.sung([], at: 10).current == nil)
    #expect(Lyrics.parse("[00:10]").first?.text == "♪")
    #expect(Lyrics.parse("no timestamps").isEmpty)
}

@Suite
@MainActor
struct TimerTests {
    @Test func countdownPauseAndFinish() {
        let center = TimerCenter(persist: false)
        center.add(minutes: 1, label: "tea")
        let now = Date()
        #expect(center.timers[0].running)
        #expect(abs(center.timers[0].remaining(at: now) - 60) < 2)
        #expect(abs(center.timers[0].progress(at: now.addingTimeInterval(30)) - 0.5) < 0.05)
        center.pause(center.timers[0].id)
        #expect(!center.timers[0].running)
        #expect(abs((center.timers[0].pausedRemaining ?? 0) - 60) < 2)
        center.resume(center.timers[0].id)
        #expect(center.timers[0].running)
        var finished = 0
        center.onFinish = { _ in finished += 1 }
        center.tick(now: Date().addingTimeInterval(120), sound: false)
        #expect(center.timers[0].ringing)
        #expect(finished == 1)
        center.cancel(center.timers[0].id)
        #expect(center.timers.isEmpty)
    }

    @Test func extendAddsAMinuteAndPresetsExist() {
        let center = TimerCenter(persist: false)
        center.add(minutes: 5, label: "focus")
        let id = center.timers[0].id
        let before = center.timers[0].endsAt
        center.extend(id, minutes: 1)
        #expect(abs((center.timers[0].endsAt?.timeIntervalSince(before ?? Date()) ?? 0) - 60) < 1)
        #expect(center.timers[0].total == 360)
        #expect(TimerCenter.presets.contains(25))
    }
}

@Test func batteryMarksFireOnceUntilTheChargerReturns() {
    let on = PowerEvents.State(adapter: true, percent: 80, charging: true, present: true)
    let off = PowerEvents.State(adapter: false, percent: 40, charging: false, present: true)
    var warned: Set<Int> = []
    let unplugged = PowerEvents.transitions(from: on, to: off, warned: &warned)
    #expect(unplugged.count == 1)
    let drop = PowerEvents.State(adapter: false, percent: 20, charging: false, present: true)
    let low = PowerEvents.transitions(from: off, to: drop, warned: &warned)
    #expect(low.count == 1)
    let again = PowerEvents.transitions(from: drop, to: PowerEvents.State(adapter: false, percent: 18, charging: false, present: true), warned: &warned)
    #expect(again.isEmpty)
    let deep = PowerEvents.transitions(from: drop, to: PowerEvents.State(adapter: false, percent: 5, charging: false, present: true), warned: &warned)
    #expect(deep.count == 2)
    let back = PowerEvents.transitions(from: drop, to: on, warned: &warned)
    #expect(warned.isEmpty)
    #expect(back.count == 1)
    let full = PowerEvents.transitions(from: PowerEvents.State(adapter: true, percent: 99, charging: true, present: true),
                                      to: PowerEvents.State(adapter: true, percent: 100, charging: false, present: true), warned: &warned)
    #expect(full.count == 1)
    #expect(PowerEvents.transitions(from: off, to: PowerEvents.State(adapter: false, percent: 10, charging: false, present: false), warned: &warned).isEmpty)
}

@Test func alertsWaitAndThenFire() {
    var clock = AlertMemory()
    let now = Date(timeIntervalSince1970: 10_000)
    var hot = SystemSnapshot()
    hot.cpu = 95
    hot.cpuReady = true
    hot.memoryUsed = 9
    hot.memoryTotal = 10
    hot.temperature = 99
    hot.battery = BatteryInfo(present: true, percent: 10, charging: false, onAdapter: false)
    let first = AlertRules.signals(hot, now: now, cpuLimit: 90, memoryLimit: 90, batteryLimit: 15, heatLimit: 95, workDone: true, memory: &clock)
    #expect(first.contains(.memory))
    #expect(first.contains(.battery))
    #expect(!first.contains(.cpu))
    #expect(!first.contains(.heat))
    let later = AlertRules.signals(hot, now: now.addingTimeInterval(61), cpuLimit: 90, memoryLimit: 90, batteryLimit: 15, heatLimit: 95, workDone: true, memory: &clock)
    #expect(later.contains(.cpu))
    #expect(later.contains(.heat))
    var calm = SystemSnapshot()
    calm.cpu = 10
    calm.cpuReady = true
    calm.temperature = 40
    calm.battery = BatteryInfo(present: true, percent: 80, onAdapter: true)
    var doneClock = AlertMemory(heavySince: now.addingTimeInterval(-300), calmSince: now.addingTimeInterval(-50))
    let done = AlertRules.signals(calm, now: now, cpuLimit: 90, memoryLimit: 90, batteryLimit: 15, heatLimit: 95, workDone: true, memory: &doneClock)
    #expect(done.contains { if case .done = $0 { return true }; return false })
}

@Test func aiEndpointsKeepAFullPathAndFillTheRest() {
    #expect(AIService.endpoint("https://api.openai.com/v1", fallback: AIService.Provider.openai.defaultBase, suffix: "/chat/completions", already: "/chat/completions")?.absoluteString == "https://api.openai.com/v1/chat/completions")
    #expect(AIService.endpoint("https://api.groq.com/openai/v1/chat/completions", fallback: "", suffix: "/chat/completions", already: "/chat/completions")?.absoluteString == "https://api.groq.com/openai/v1/chat/completions")
    #expect(AIService.endpoint("https://api.openai.com/v1/", fallback: AIService.Provider.openai.defaultBase, suffix: "/chat/completions", already: "/chat/completions")?.absoluteString == "https://api.openai.com/v1/chat/completions")
    #expect(AIService.endpoint("", fallback: AIService.Provider.anthropic.defaultBase, suffix: "/v1/messages", already: "/messages")?.absoluteString == "https://api.anthropic.com/v1/messages")
    #expect(AIService.endpoint("http://[", fallback: "http://[", suffix: "/chat/completions", already: "/chat/completions") == nil)
    #expect(AIService.Provider.ollama.defaultBase.contains("11434"))
    #expect(AIService.Provider.gemini.defaultBase.contains("googleapis"))
    #expect(!AIService.Provider.custom.defaultModel.isEmpty == false)
    #expect(AIService.Provider.openrouter.anthropicWire == false)
    #expect(AIService.Provider.anthropic.anthropicWire)
}

@Suite
@MainActor
struct FanCurveTests {
    @Test func smartRisesAndHeatOverrides() {
        let name = "savisul.fans.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let fans = FanControl(defaults: defaults, live: false)
        let reading = FanReading(id: 0, actual: 1200, minimum: 1000, maximum: 5000)
        fans.update(fans: [reading], temperature: 50)
        fans.mode = .smart
        #expect(fans.target() == nil)
        fans.update(fans: [reading], temperature: 74)
        let mid = fans.target()
        #expect(mid != nil)
        #expect((mid ?? 0) > 1000 && (mid ?? 0) < 5000)
        fans.update(fans: [reading], temperature: 96)
        #expect(fans.target() == 5000)
        fans.mode = .auto
        #expect(fans.target() == nil)
        defaults.removePersistentDomain(forName: name)
    }
}

@Test func claudeLimitLineAndOpenCodeShape() {
    #expect(ClaudeReader.limitReset(in: "usage limit reached|1710000000")?.timeIntervalSince1970 == 1_710_000_000)
    #expect(ClaudeReader.limitReset(in: "all good") == nil)
    let message = Data(#"{"id":"m1","role":"assistant","sessionID":"s1","modelID":"gpt","cost":0.2,"tokens":{"input":10,"output":5,"reasoning":1,"cache":{"read":2,"write":3}},"time":{"created":1710000000,"completed":1710000005},"path":{"cwd":"/work/SAVISUL"}}"#.utf8)
    let object = AgentLog.object(message)
    #expect(object?["role"] as? String == "assistant")
    let tokens = object?["tokens"] as? [String: Any]
    #expect(tokens?["output"] as? Int == 5)
    #expect(AgentTime.parse((object?["time"] as? [String: Any])?["completed"]) != nil)
}
