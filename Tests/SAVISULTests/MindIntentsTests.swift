#if MOULD_ENGINE
import Foundation
import MouldEngine
import Testing
@testable import SAVISUL

/// Everyday requests the assistant handles itself, and the few tools everything else takes to the model.
@Suite(.serialized)
@MainActor
struct MindIntentsTests {
    private func tool(_ text: String) -> (name: String, arguments: JSONValue)? {
        if case .tool(let name, let arguments) = MindIntents.route(text) { return (name.rawValue, arguments) }
        return nil
    }

    private func tools(_ text: String) -> Set<String>? {
        if case .model(let tools) = MindIntents.route(text) { return tools }
        return nil
    }

    @Test func featuresAreSwitchedByTheirNames() {
        #expect(tool("Выключи панду")?.arguments == ["id": "islandPanda", "on": false])
        #expect(tool("вимкни панду")?.arguments == ["id": "islandPanda", "on": false])
        #expect(tool("turn off the panda")?.arguments == ["id": "islandPanda", "on": false])
        #expect(tool("верни панду")?.arguments == ["id": "islandPanda", "on": true])
        // The longest name wins: the panda's sounds, not the panda.
        #expect(tool("выключи звуки панды")?.arguments == ["id": "pandaSounds", "on": false])
        #expect(tool("выключи текст песен")?.arguments == ["id": "islandLyrics", "on": false])
        #expect(tool("включи островок")?.arguments == ["id": "island", "on": true])
        // Too broad to be one switch, or the person's own: the model hears it instead.
        #expect(tool("выключи звук") == nil)
        #expect(tool("выключи ассистента") == nil)
    }

    @Test func everydayRequestsRunStraightAway() {
        for text in ["Проверь мой Mac", "Перевір мій Mac", "What's using my CPU?", "Сколько свободной памяти?", "почему тормозит макбук", "check my mac"] {
            #expect(tool(text)?.name == "mac.health", "\(text)")
        }
        #expect(tool("Разбери загрузки по папкам")?.name == "files.sort_folder")
        #expect(tool("Разбери загрузки по папкам")?.arguments["folder"] == "~/Downloads")
        #expect(tool("розбери робочий стіл")?.arguments["folder"] == "~/Desktop")
        for text in ["Какие у меня встречи сегодня?", "що в мене в календарі", "what meetings do I have today"] {
            #expect(tool(text)?.name == "calendar.upcoming", "\(text)")
        }
        #expect(tool("Что делают мои агенты?")?.name == "agents.status")
        #expect(tool("що робить claude code")?.name == "agents.status")
        #expect(MindIntents.route("Найди фото кота") == .photos)
        for text in ["Привет", "Привет! Что ты умеешь?", "что ты умеешь", "help", "Добрый день"] {
            #expect(MindIntents.route(text) == .answer(MindPhrases.capabilities.text), "\(text)")
        }
    }

    @Test func everythingElseGoesToTheModelWithFewTools() throws {
        // Plain questions get no tools at all: the model just answers.
        #expect(tools("Переведи на английский: доброе утро, как дела?") == [])
        #expect(tools("Сколько будет 15% от 2400?") == [])
        #expect(tools("создай встречу завтра в 10") != nil)
        #expect(tools("запусти claude в проекте site") != nil)
        let files = try #require(tools("Найди файл с расширением pdf в загрузках"))
        #expect(files.contains("files.search"))
        #expect(files.count <= 6)
        let automation = try #require(tools("Создай автоматизацию, которая переименовывает новые pdf по дате"))
        #expect(automation.contains("automations.create"))
        #expect(automation.count <= 8)
    }

    @Test func thePersonsOwnAIAnswersWhenConnected() {
        func profile(_ id: String, backend: String, local: Bool) -> ModelProfile {
            ModelProfile(id: id, backend: backend, model: id, title: id, locality: local ? .local : .cloud, contextTokens: 16_000, maxOutputTokens: 1000,
                         tools: true, vision: false, json: true, quality: 0.5, inputCost: 0, outputCost: 0, firstToken: 1, tokensPerSecond: 50)
        }
        let deepseek = profile("deepseek:deepseek-chat", backend: "deepseek", local: false)
        let qwen = profile("local:" + LocalModels.recommendedID, backend: "local", local: true)
        let small = profile("local:qwen2.5-1.5b-instruct-q4_k_m", backend: "local", local: true)
        // A key connected: it thinks with that model.
        #expect(MindHost.choose([small, qwen, deepseek], mode: .localFirst, personal: false, personalToCloud: false) == deepseek.id)
        // What the person selected doesn't go to the cloud unless they allowed it; then the best model on this Mac answers.
        #expect(MindHost.choose([small, qwen, deepseek], mode: .localFirst, personal: true, personalToCloud: false) == qwen.id)
        #expect(MindHost.choose([small, qwen, deepseek], mode: .localFirst, personal: true, personalToCloud: true) == deepseek.id)
        // Kept to this Mac, or no key: the recommended local model, or the router's choice.
        #expect(MindHost.choose([small, qwen, deepseek], mode: .localOnly, personal: false, personalToCloud: true) == qwen.id)
        #expect(MindHost.choose([small, qwen], mode: .localFirst, personal: false, personalToCloud: false) == qwen.id)
        #expect(MindHost.choose([small], mode: .localFirst, personal: false, personalToCloud: false) == nil)
        // A cloud model that can't answer right now hands over; a refusal doesn't.
        #expect(MindHost.worthAnotherModel(.backend("401", retryable: false)))
        #expect(MindHost.worthAnotherModel(.unavailable("offline")))
        #expect(!MindHost.worthAnotherModel(.declined("no")))
    }

    @Test func theRecommendedModelIsTheBetterOne() throws {
        #expect(LocalModels.recommended.url.host == "huggingface.co")
        #expect(LocalModels.recommended.sha256.count == 64)
        #expect(LocalModels.recommended.bytes > 2_000_000_000)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("models-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        for name in [LocalModels.recommended.file, LocalModels.earlier.file] { try Data([0]).write(to: folder.appendingPathComponent(name)) }
        let models = LocalModels.installed(in: [folder])
        let better = try #require(models.first { $0.id == LocalModels.recommendedID })
        let smaller = try #require(models.first { $0.id != LocalModels.recommendedID })
        #expect(better.title == "Qwen3 4B")
        #expect(smaller.title == "Qwen 2.5 1.5B")
        #expect(better.quality > smaller.quality)
    }

    @Test func everyRoutedToolExists() async throws {
        var configuration = EngineConfiguration(storage: nil)
        configuration.llamaServer = nil
        configuration.macAdapters = true
        let engine = try await MouldEngine(configuration: configuration, broker: DeclineAllBroker())
        let automations = AutomationEngine(store: FileManager.default.temporaryDirectory.appendingPathComponent("intents-\(UUID().uuidString).json"))
        try await engine.registry.register(MindTools.automations(automations) + MindTools.general)
        let names = Set(await engine.registry.names.map(\.rawValue))
        let samples = ["Найди файл pdf", "переименуй файл", "прочитай файл", "разложи файлы", "автоматизация", "буфер", "конвертируй картинку", "положи на полку",
                       "запомни", "покажи в островке", "что за процессы", "встреча", "агенты", "функции"]
        for sample in samples {
            for tool in MindIntents.tools(for: PhotoWords.tokens(sample)) {
                #expect(names.contains(tool), "\(sample) → \(tool) isn't a tool")
            }
        }
        await engine.shutdown()
    }
}
#endif

#if MOULD_ENGINE
/// Automations people ask for most become automations without a model; the person still sees them before they're made.
@Suite(.serialized)
@MainActor
struct MindAutomationIntentsTests {
    private func made(_ text: String) -> JSONValue? {
        if case .tool(let name, let arguments) = MindIntents.route(text), name == "automations.create" { return arguments }
        return nil
    }

    @Test func commonAutomationsAreUnderstood() throws {
        let airpods = try #require(made("Создай автоматизацию: когда подключаю AirPods, ставь громкость 30%"))
        #expect(airpods["trigger"]?["kind"] == "deviceConnected")
        #expect(airpods["trigger"]?["text"] == "AirPods")
        #expect(airpods["steps"]?.array?.first?["kind"] == "setVolume")
        #expect(airpods["steps"]?.array?.first?["number"]?.int == 30)
        #expect(airpods["name"]?.string == "Когда подключаю AirPods, ставь громкость 30%")

        let battery = try #require(made("Когда батарея ниже 15%, выключи микрофоны и покажи «Заряди Mac»"))
        #expect(battery["trigger"]?["kind"] == "batteryBelow")
        #expect(battery["trigger"]?["number"]?.int == 15)
        #expect(battery["steps"]?.array?.compactMap { $0["kind"]?.string } == ["muteMics", "notice"])
        #expect(battery["steps"]?.array?.last?["text"] == "Заряди Mac")

        let agent = try #require(made("когда агент закончит, проиграй звук"))
        #expect(agent["trigger"]?["kind"] == "agentFinished")
        #expect(agent["steps"]?.array?.first?["kind"] == "sound")

        let morning = try #require(made("каждый день в 9:00 ставь громкость 40"))
        #expect(morning["trigger"]?["number"]?.int == 9 * 60)
        #expect(morning["steps"]?.array?.first?["number"]?.int == 40)

        // Nothing it can place: the model hears it.
        #expect(made("когда у меня встреча?") == nil)
        #expect(made("создай автоматизацию для фото") == nil)
    }

    @Test func translationsAreOnlyTranslations() {
        #expect(MindIntents.instructions(for: PhotoWords.tokens("Переведи на английский: доброе утро")) != nil)
        #expect(MindIntents.instructions(for: PhotoWords.tokens("переклади українською: good evening")) != nil)
        #expect(MindIntents.instructions(for: PhotoWords.tokens("Сколько будет 15% от 2400?")) == nil)
    }
}
#endif
