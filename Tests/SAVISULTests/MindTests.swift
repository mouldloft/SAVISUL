#if MOULD_ENGINE
import Foundation
import MouldEngine
import Testing
@testable import SAVISUL

/// SAVISUL's side of the assistant: its tools, models and words, on a private engine and stores in a temporary folder.
@Suite(.serialized)
@MainActor
final class MindTests {
    let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("savisul-mind-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    /// An engine that keeps nothing on disk, runs no local models and asks nobody.
    private func engine(tools: [any Tool]) async throws -> MouldEngine {
        var configuration = EngineConfiguration(storage: nil)
        configuration.llamaServer = nil
        configuration.macAdapters = false
        // The temporary folder lives under /var, which apps never get to see otherwise.
        configuration.systemRoots = []
        let engine = try await MouldEngine(configuration: configuration, broker: DeclineAllBroker())
        try await engine.registry.register(tools)
        return engine
    }

    private func speaking<T>(_ language: Language, _ work: () throws -> T) rethrows -> T {
        let previous = Suite.shared.language
        Suite.shared.language = language
        defer { Suite.shared.language = previous }
        return try work()
    }

    @Test func cloudModelsAreProfiledByProvider() {
        let opus = CloudModels.profile(provider: .anthropic, model: "claude-opus-5-5")
        #expect(opus.locality == .cloud)
        #expect(opus.contextTokens == 200_000)
        #expect(opus.quality > CloudModels.profile(provider: .anthropic, model: "claude-haiku-4-5").quality)
        #expect(CloudModels.profile(provider: .gemini, model: "gemini-2.0-flash").contextTokens == 1_000_000)
        // Ollama runs on this Mac, so personal requests may go to it.
        #expect(CloudModels.profile(provider: .ollama, model: "llama3.1").locality == .local)
    }

    @Test func localModelsAreFoundOncePerModel() throws {
        let other = directory.appendingPathComponent("other")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        for name in ["big-7b-00001-of-00002.gguf", "big-7b-00002-of-00002.gguf", "qwen2.5-1.5b-instruct-q4_k_m.gguf", "notes.txt"] {
            try Data([0]).write(to: directory.appendingPathComponent(name))
        }
        try Data([0]).write(to: other.appendingPathComponent("qwen2.5-1.5b-instruct-q4_k_m.gguf"))
        let models = LocalModels.installed(in: [directory, other])
        // A split model counts once, by its first part; the same model in two folders counts once.
        #expect(models.map(\.id).sorted() == ["big-7b-00001-of-00002", "qwen2.5-1.5b-instruct-q4_k_m"])
        let big = try #require(models.first { $0.id.hasPrefix("big") })
        let small = try #require(models.first { $0.id.hasPrefix("qwen") })
        #expect(small.title == LocalModels.earlier.title)
        #expect(big.quality > small.quality)
        #expect(big.tokensPerSecond < small.tokensPerSecond)
    }

    @Test func everyToolRegistersAndIsNamedInEveryLanguage() async throws {
        var configuration = EngineConfiguration(storage: nil)
        configuration.llamaServer = nil
        let engine = try await MouldEngine(configuration: configuration, broker: DeclineAllBroker())
        let automations = AutomationEngine(store: directory.appendingPathComponent("automations.json"))
        try await engine.registry.register(MindTools.automations(automations) + MindTools.general)
        let names = await engine.registry.names
        #expect(names.contains("automations.create"))
        #expect(names.contains("files.sort_folder"))
        for language in Language.allCases {
            let missing = speaking(language) { names.filter { MindPhrases.tool($0, "?") == "?" } }
            #expect(missing.isEmpty, "No \(language.rawValue) title for \(missing)")
        }
    }

    @Test func automationsAreMadeOnlyForGrantedFolders() async throws {
        let automations = AutomationEngine(store: directory.appendingPathComponent("automations.json"))
        let inbox = directory.appendingPathComponent("Inbox")
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        let engine = try await engine(tools: MindTools.automations(automations))
        engine.grant(inbox, writable: true)
        let origin = Origin(agent: .person, taskID: "scans")
        let create = ToolCall(tool: "automations.create", arguments: [
            "name": "New scans",
            "trigger": ["kind": "fileAdded", "text": .string(inbox.path), "extensions": "pdf"],
            "steps": [["kind": "notice", "text": "A new scan arrived"]]
        ])
        _ = try await engine.runtime.execute(create, origin: origin)
        #expect(automations.items.map(\.name) == ["New scans"])
        #expect(automations.items.first?.trigger.text.hasSuffix("/Inbox") == true)
        // Undo takes it away again.
        try await engine.undo(taskID: "scans")
        #expect(automations.items.isEmpty)

        // A folder that wasn't granted is refused before anything is made.
        let elsewhere = ToolCall(tool: "automations.create", arguments: [
            "name": "Watch documents", "trigger": ["kind": "fileAdded", "text": "~/Documents"], "steps": [["kind": "notice", "text": "x"]]
        ])
        await #expect(throws: MouldError.self) { try await engine.runtime.execute(elsewhere, origin: origin) }
        #expect(automations.items.isEmpty)

        // A model can't make one without asking, and nobody here says yes.
        let asked = Origin(agent: .model("test"), taskID: "model")
        await #expect(throws: MouldError.declined("Create an automation")) { try await engine.runtime.execute(create, origin: asked) }
        #expect(automations.items.isEmpty)
    }

    @Test func theAssistantCantSwitchOffItsOwnSafeguards() async throws {
        let engine = try await engine(tools: MindTools.general)
        for id in ["assistant", "assistantHotkey", "agentApprovals", "faceUnlock"] {
            let call = ToolCall(tool: "savisul.feature", arguments: ["id": .string(id), "on": false])
            await #expect(throws: MouldError.denied("\(id) is changed only by the person")) {
                try await engine.runtime.execute(call, origin: .person)
            }
        }
    }

    @Test func consentIsSaidInThePersonsLanguage() {
        speaking(.ru) {
            let conversation = MindConversation()
            let preview = ToolPreview(summary: "Sort 5 items into 2 folders",
                                      changes: [Change(.move, "/Users/me/Downloads/a.pdf", "/Users/me/Downloads/Документы/a.pdf")], omitted: 4)
            let request = ConfirmationRequest(taskID: "t", title: "Sort a folder",
                                              items: [.init(tool: "files.sort_folder", toolTitle: "Sort a folder", risk: .reversible, preview: preview)],
                                              tainted: false)
            conversation.confirm(request)
            #expect(conversation.items.last?.text == "Разобрать папку")
            #expect(MindPhrases.change(preview.changes[0]) == "a.pdf → Документы")
            #expect(MindPhrases.andMore(4) == "и ещё 4")
            #expect(conversation.pendingConsent.map(\.id) == [request.id])
            // No answer in time counts as no, and says so.
            conversation.answered(request.id, .expired)
            #expect(conversation.pendingConsent.isEmpty)
            #expect(conversation.items.last?.status == .declined)
            #expect(conversation.items.last?.detail == MindPhrases.expired.text)
            #expect(MindPhrases.error(.declined("Sort a folder")) == "Не выполнено: вы отказались")
        }
    }

    @Test func stepsAndFailuresFollowTheLanguage() {
        speaking(.fr) {
            let conversation = MindConversation()
            conversation.begin(MindRequest("Range mes téléchargements", taskID: "t"))
            let call = ToolCall(tool: "files.trash", arguments: ["paths": ["/tmp/a"]])
            conversation.apply(.toolStarted(call, title: "Move to Trash"))
            #expect(conversation.items.last?.text == "Mettre à la corbeille")
            conversation.apply(.toolFailed(call, error: .declined("Move to Trash")))
            #expect(conversation.items.last?.status == .declined)
            conversation.fail(.cancelled)
            #expect(conversation.items.last?.kind == .note)
            conversation.end()
            #expect(conversation.running == nil)
        }
    }

    @Test func withdrawnTextLeavesTheConversation() {
        let conversation = MindConversation()
        conversation.begin(MindRequest("What time is it?", taskID: "t"))
        conversation.apply(.text("I can use the function test__clock."))
        conversation.apply(.retracted)
        conversation.apply(.text("It's 12:00."))
        conversation.apply(.finished(answer: "It's 12:00."))
        #expect(conversation.items.filter { $0.kind == .answer }.map(\.text) == ["It's 12:00."])
    }

    @Test func healthReportsAreSaidFromTheNumbers() {
        let output = ToolOutput([
            "resources": ["memoryTotalGB": 16, "memoryAvailableGB": 1, "cpuLoadPercent": 20, "thermal": "nominal", "onBattery": false],
            "diskFreeGB": 200, "diskTotalGB": 500,
            "topMemory": [["name": "Safari", "memoryMB": 2048]],
            "topCPU": [["name": "Xcode", "cpuPercent": 80]],
            "findings": ["Memory is nearly full."]
        ])
        let english = speaking(.en) { MindReport.describe("mac.health", output) }
        #expect(english.hasPrefix("Memory is nearly full."))
        #expect(english.contains("Safari"))
        #expect(english.contains("Xcode keeps 0.8 processor cores busy"))
        #expect(english.contains("Safari (2.0 GB)"))
        let russian = speaking(.ru) { MindReport.describe("mac.health", output) }
        #expect(russian.hasPrefix("Память почти заполнена."))
        #expect(!russian.contains("nearly"))
        #expect(speaking(.ru) { MindReport.describe("files.sort_folder", ToolOutput(["moved": [], "skipped": []])) } == MindPhrases.nothingToSort.ru)
    }

    @Test func aDownloadIsCheckedByteForByte() throws {
        let file = directory.appendingPathComponent("model.gguf")
        try Data("hello".utf8).write(to: file)
        #expect(ModelDownload.sha256(of: file) == "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
        #expect(ModelDownload.sha256(of: directory.appendingPathComponent("missing")) == nil)
        #expect(LocalModels.recommended.sha256.count == 64)
    }

    @Test func theAssistantIsAFeatureWithItsOwnShortcut() {
        let group = FeatureGroup.all.first { $0.id == "assistant" }
        #expect(group?.main.key == \SuiteSettings.assistant)
        #expect(group?.options.first?.keys == ["⌃", "⌥", "H"])
        #expect(AutomationEngine.featureKey("assistantHotkey") == \SuiteSettings.assistantHotkey)
        // ⌃⌥H isn't taken by another SAVISUL shortcut.
        let shortcuts = FeatureGroup.all.flatMap { [$0.main] + $0.options }.map(\.keys).filter { !$0.isEmpty }
        #expect(shortcuts.filter { $0 == ["⌃", "⌥", "H"] }.count == 1)
    }
}
#endif
