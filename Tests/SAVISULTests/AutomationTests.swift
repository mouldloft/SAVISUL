import Foundation
import Testing
@testable import SAVISUL

@Suite
@MainActor
final class AutomationTests {
    let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("savisul-automation-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    @Test func renamePatternsFillTheirTokens() throws {
        let file = directory.appendingPathComponent("invoice.pdf")
        try Data([1]).write(to: file)
        let renamed = try AutomationEngine.rename([file], pattern: "{date} {name}")
        let today = DateFormatter()
        today.dateFormat = "yyyy-MM-dd"
        #expect(renamed.map(\.lastPathComponent) == ["\(today.string(from: Date())) invoice.pdf"])
        let numbered = try AutomationEngine.rename(renamed, pattern: "Scan {n}.{ext}")
        #expect(numbered.map(\.lastPathComponent) == ["Scan 1.pdf"])
        // An empty pattern falls back to "{date} {name}" rather than wiping the name.
        #expect(try AutomationEngine.rename(numbered, pattern: "  ").first?.lastPathComponent.hasSuffix(" Scan 1.pdf") == true)
    }

    @Test func extensionListsAreForgiving() {
        #expect(AutomationEngine.extensions("PDF, .jpg;png  heic") == ["pdf", "jpg", "png", "heic"])
        #expect(AutomationEngine.extensions("").isEmpty)
    }

    @Test func weekdaysStartOnMonday() {
        let calendar = Calendar(identifier: .gregorian)
        let monday = calendar.date(from: DateComponents(year: 2026, month: 10, day: 5))!
        let sunday = calendar.date(from: DateComponents(year: 2026, month: 10, day: 11))!
        #expect(AutomationEngine.weekday(monday) == 1)
        #expect(AutomationEngine.weekday(sunday) == 7)
        #expect(AutomationEngine.clock(9 * 60 + 5) == "09:05")
    }

    @Test func automationsSurviveSaving() throws {
        let original = AutomationTemplates.all[1]
        let data = try JSONEncoder().encode([original])
        let back = try JSONDecoder().decode([Automation].self, from: data)
        #expect(back == [original])
    }

    @Test func templatesAreComplete() {
        let templates = AutomationTemplates.all
        #expect(templates.count == 5)
        #expect(Set(templates.map(\.trigger.kind)) == [.deviceConnected, .fileAdded, .appLaunched, .agentFinished, .batteryBelow])
        for template in templates {
            #expect(!template.steps.isEmpty)
            for step in template.steps where step.kind == .feature {
                #expect(AutomationEngine.featureKey(step.text) != nil)
            }
        }
    }

    @Test func conditionsCheckTheMac() {
        let engine = AutomationEngine()
        #expect(engine.passes(AutomationCondition(kind: .timeBetween, number: 0, number2: 24 * 60)))
        #expect(engine.passes(AutomationCondition(kind: .weekdays, weekdays: Array(1...7))))
        #expect(!engine.passes(AutomationCondition(kind: .weekdays, weekdays: [AutomationEngine.weekday(Date()) % 7 + 1])))
        #expect(!engine.passes(AutomationCondition(kind: .appRunning, text: "com.example.not-installed")))
        #expect(engine.passes(AutomationCondition(kind: .appNotRunning, text: "com.example.not-installed")))
    }

    @Test func aFolderReportsFilesOnceTheyAreWhole() async throws {
        let watcher = FolderWatcher(url: directory)
        var seen: [String] = []
        watcher.onAdded = { seen.append($0.lastPathComponent) }
        defer { watcher.stop() }
        try Data([1, 2, 3]).write(to: directory.appendingPathComponent("report.pdf"))
        try Data([1]).write(to: directory.appendingPathComponent("movie.mp4.crdownload"))
        for _ in 0..<40 where !seen.contains("report.pdf") { try await Task.sleep(nanoseconds: 150_000_000) }
        #expect(seen == ["report.pdf"])
    }

    @Test func stepsRunInOrderOnTheFile() async throws {
        let file = directory.appendingPathComponent("photo.png")
        try Data([1]).write(to: file)
        let target = directory.appendingPathComponent("Sorted")
        var automation = Automation(name: "Sort", trigger: AutomationTrigger(kind: .fileAdded, text: directory.path))
        automation.showInIsland = false
        automation.steps = [AutomationStep(kind: .renameFile, text: "Shot {n}"), AutomationStep(kind: .moveFile, text: target.path)]
        let engine = AutomationEngine()
        engine.run(automation, event: AutomationEvent(title: "photo.png", files: [file]))
        for _ in 0..<40 where engine.history.isEmpty { try await Task.sleep(nanoseconds: 50_000_000) }
        #expect(engine.history.first?.ok == true)
        #expect(FileManager.default.fileExists(atPath: target.appendingPathComponent("Shot 1.png").path))
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    /// An engine on a private file, so tests never touch the person's own automations.
    private func engine(_ automations: [Automation]) -> (AutomationEngine, URL) {
        let store = directory.appendingPathComponent("automations-\(UUID().uuidString).json")
        let engine = AutomationEngine(store: store)
        for automation in automations { engine.add(automation) }
        return (engine, store)
    }

    private func quiet(_ name: String, _ trigger: AutomationTrigger, enabled: Bool = true, conditions: [AutomationCondition] = []) -> Automation {
        var automation = Automation(name: name, enabled: enabled, trigger: trigger, conditions: conditions,
                                    steps: [AutomationStep(kind: .wait, number: 0)])
        automation.showInIsland = false
        return automation
    }

    private func settle(_ engine: AutomationEngine, runs: Int) async throws {
        for _ in 0..<40 where engine.history.count < runs { try await Task.sleep(nanoseconds: 50_000_000) }
        try await Task.sleep(nanoseconds: 150_000_000)
    }

    @Test func onlyTheMatchingAgentFires() async throws {
        let (engine, store) = engine([
            quiet("Codex done", AutomationTrigger(kind: .agentFinished, text: "codex")),
            quiet("Any agent", AutomationTrigger(kind: .agentFinished)),
            quiet("Claude done", AutomationTrigger(kind: .agentFinished, text: "claude")),
            quiet("Switched off", AutomationTrigger(kind: .agentFinished), enabled: false)
        ])
        engine.agentFinished(AgentFinish(kind: .codex, project: "SAVISUL", duration: 120))
        try await settle(engine, runs: 2)
        #expect(Set(engine.history.map(\.name)) == ["Codex done", "Any agent"])
        #expect(engine.history.allSatisfy { $0.detail == "Codex · SAVISUL" })
        #expect(FileManager.default.fileExists(atPath: store.path))
        #expect(engine.items.first { $0.name == "Codex done" }?.runs == 1)
    }

    @Test func fileTriggersMatchFolderAndType() async throws {
        let (engine, _) = engine([
            quiet("PDFs", AutomationTrigger(kind: .fileAdded, text: directory.path, extensions: "pdf")),
            quiet("Elsewhere", AutomationTrigger(kind: .fileAdded, text: "~/Downloads"))
        ])
        engine.fileAdded(directory.appendingPathComponent("notes.txt"))
        engine.fileAdded(directory.appendingPathComponent("Invoice.PDF"))
        try await settle(engine, runs: 1)
        #expect(engine.history.map(\.name) == ["PDFs"])
    }

    @Test func conditionsAndRepeatsHoldARunBack() async throws {
        let (engine, _) = engine([
            quiet("Needs an app", AutomationTrigger(kind: .appLaunched, text: "com.example.editor"),
                  conditions: [AutomationCondition(kind: .appRunning, text: "com.example.not-installed")]),
            quiet("Once", AutomationTrigger(kind: .appLaunched, text: "com.example.editor"))
        ])
        engine.appChanged("com.example.editor", name: "Editor", launched: true)
        engine.appChanged("com.example.editor", name: "Editor", launched: true)
        engine.appChanged("com.example.editor", name: "Editor", launched: false)
        try await settle(engine, runs: 1)
        #expect(engine.history.map(\.name) == ["Once"])
    }

    @Test func savedAutomationsComeBack() throws {
        let (first, store) = engine([quiet("Kept", AutomationTrigger(kind: .schedule, number: 9 * 60))])
        first.setEnabled(first.items[0].id, false)
        let second = AutomationEngine(store: store)
        #expect(second.items.map(\.name) == ["Kept"])
        #expect(second.items.first?.enabled == false)
    }

    @Test func aFailingStepStopsTheRunAndSaysWhy() async throws {
        var automation = Automation(name: "Broken", trigger: AutomationTrigger(kind: .schedule))
        automation.showInIsland = false
        automation.steps = [AutomationStep(kind: .renameFile, text: "x"), AutomationStep(kind: .sound)]
        let engine = AutomationEngine()
        engine.run(automation)
        for _ in 0..<40 where engine.history.isEmpty { try await Task.sleep(nanoseconds: 50_000_000) }
        #expect(engine.history.first?.ok == false)
        #expect(engine.running.isEmpty)
    }
}
