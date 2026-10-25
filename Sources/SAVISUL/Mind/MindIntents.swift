#if MOULD_ENGINE
import Foundation
import MouldEngine

/// Everyday requests SAVISUL understands by itself: said plainly, they run straight away, the same way every time, with
/// the answer in the person's language. Everything else goes to the model with only the tools its words point to: a
/// small model on this Mac, handed thirty-five tools, picks the wrong one or goes in circles.
@MainActor
enum MindIntents {
    enum Route: Equatable {
        /// One of SAVISUL's tools, run straight away.
        case tool(ToolName, JSONValue)
        /// An answer SAVISUL knows itself.
        case answer(String)
        /// Photo search, which has a way of its own.
        case photos
        /// The model, with just these tools; none means a plain answer.
        case model(tools: Set<String>)
    }

    static func route(_ text: String) -> Route {
        let words = PhotoWords.tokens(text)
        guard !words.isEmpty else { return .model(tools: []) }
        if PhotoSearch.isPhotoRequest(text) { return .photos }
        if let created = automation(words, text) { return .tool("automations.create", created) }
        if let switched = feature(words) { return .tool("savisul.feature", ["id": .string(switched.id), "on": .bool(switched.on)]) }
        if let folder = sorting(words) {
            return .tool("files.sort_folder", ["folder": .string(folder), "by": "type", "names": MindPhrases.folderNames])
        }
        if health(words) { return .tool("mac.health", [:]) }
        if calendar(words) { return .tool("calendar.upcoming", ["limit": 8]) }
        if agents(words) { return .tool("agents.status", [:]) }
        if greeting(words) { return .answer(MindPhrases.capabilities.text) }
        return .model(tools: tools(for: words))
    }

    // MARK: Words

    private struct Stems {
        var prefixes: [String] = []
        var whole: Set<String> = []

        func any(_ words: [String]) -> Bool {
            words.contains { word in whole.contains(word) || prefixes.contains { word.hasPrefix($0) } }
        }
    }

    private static let mac = Stems(prefixes: ["мак", "компьют", "компют", "систем", "ноутбук"], whole: ["mac", "macbook", "computer", "laptop", "system"])
    private static let check = Stems(prefixes: ["провер", "перевір", "диагност", "діагност", "проскан"], whole: ["check", "scan", "inspect", "diagnose"])
    private static let slow = Stems(prefixes: ["тормоз", "лага", "гальм", "тупит", "висн", "зависа", "перегр", "нагрел", "греет", "гріє", "грієть"],
                                    whole: ["slow", "lag", "lags", "lagging", "hot", "overheating"])
    /// "What's" loses its apostrophe to the words' normal form, so it is here as "whats".
    private static let what = Stems(whole: ["что", "що", "кто", "хто", "what", "whats", "who", "whos", "which", "почему", "чому", "why"])
    private static let busy = Stems(prefixes: ["груз", "жр", "нагруж", "занима", "использ", "використ", "хава", "їсть", "ест"],
                                    whole: ["using", "uses", "eating", "eats", "taking", "hogging"])
    private static let resources = Stems(prefixes: ["процессор", "процесор", "памят", "батаре", "батар", "акумулятор", "заряд", "диск", "мест", "місц"],
                                         whole: ["cpu", "memory", "ram", "battery", "disk", "space", "storage", "processor"])
    private static let howMuch = Stems(whole: ["сколько", "скільки", "how", "much"])

    private static func health(_ words: [String]) -> Bool {
        (check.any(words) && mac.any(words)) || (slow.any(words) && mac.any(words)) || (what.any(words) && busy.any(words) && resources.any(words))
            || (howMuch.any(words) && resources.any(words)) || (words.contains("health") && mac.any(words))
    }

    private static let sort = Stems(prefixes: ["разбер", "разбир", "разлож", "рассорт", "отсорт", "сортир", "упоряд", "розбер", "розбир", "розклад",
                                               "відсорт", "посорт", "впорядк", "sort", "organi", "tidy"])
    private static let downloads = Stems(prefixes: ["загрузк", "завантаж", "download"])
    private static let desktop = Stems(prefixes: ["desktop"], whole: ["стол", "столе", "стіл", "столі"])
    private static let documents = Stems(prefixes: ["documents"], whole: ["документы", "документах", "документи", "документах"])

    /// Which folder to sort, by its name in the request.
    private static func sorting(_ words: [String]) -> String? {
        guard sort.any(words) else { return nil }
        if downloads.any(words) { return "~/Downloads" }
        if desktop.any(words) { return "~/Desktop" }
        if documents.any(words) { return "~/Documents" }
        return nil
    }

    private static let meetings = Stems(prefixes: ["встреч", "зустріч", "meeting", "календар", "calendar", "расписан", "розклад", "schedule",
                                                   "созвон", "событи", "поді", "event"])
    private static let plans = Stems(whole: ["планы", "план", "плани", "plans", "plan", "дела", "справи"])
    private static let days = Stems(whole: ["сегодня", "завтра", "сьогодні", "today", "tomorrow"])
    private static let create = Stems(prefixes: ["создай", "создать", "добав", "запланир", "назнач", "створ", "додай", "заплану", "призна", "create",
                                                 "add", "book", "запиш"])

    private static func calendar(_ words: [String]) -> Bool {
        (meetings.any(words) || (days.any(words) && plans.any(words))) && !create.any(words)
    }

    private static let agentNames = Stems(prefixes: ["агент", "agent", "claude", "codex", "cursor", "copilot", "opencode", "клод"])
    private static let order = Stems(prefixes: ["запуст", "поручи", "дай", "задач", "напиши", "напиш", "попрос", "доруч", "start", "run", "launch",
                                                "ask", "tell", "give", "открой", "відкрий", "open"])

    private static func agents(_ words: [String]) -> Bool {
        agentNames.any(words) && !order.any(words) && !create.any(words)
    }

    private static let hello = Stems(whole: ["привет", "приветик", "здравствуй", "здравствуйте", "хай", "hello", "hi", "hey", "привіт", "вітаю",
                                             "добрый", "доброе", "добрий", "доброго", "день", "утро", "вечер", "ранку", "вечора", "good", "morning",
                                             "evening", "there", "салют", "йо", "ассистент", "асистент", "savisul"])
    private static let able = Stems(prefixes: ["умеешь", "умеет", "можешь", "вмієш", "можеш", "могу", "умеешь"], whole: ["can", "able", "do"])
    private static let help = Stems(whole: ["помощь", "помоги", "допомога", "допоможи", "help", "справка", "инструкция", "інструкція"])

    private static func greeting(_ words: [String]) -> Bool {
        if words.allSatisfy({ hello.whole.contains($0) }) { return true }
        if words.count <= 2 && help.any(words) { return true }
        let asking = what.any(words) || words.contains("чем") || words.contains("чим")
        return asking && able.any(words) && words.count <= 8
    }

    // MARK: Turning a feature on or off

    private static let on = Stems(prefixes: ["включ", "верни", "вкл", "увімкн", "ввімкн", "поверни", "enable"])
    private static let off = Stems(prefixes: ["выключ", "отключ", "убер", "убра", "спрячь", "скрой", "вимкн", "відключ", "прибер", "сховай", "disable",
                                              "hide"], whole: ["off"])
    /// The person's own switches that the assistant never flips.
    private static let guarded: Set<String> = ["assistant", "assistantHotkey", "agentApprovals", "faceUnlock"]
    private static let filler: Set<String> = ["показывать", "показувати", "show", "the", "a", "an", "of", "in", "и", "і", "й", "в", "у", "with", "с", "з"]
    /// Group names too broad to stand for one switch: "выключи звук" means quiet, not the per-app mixer.
    private static let broad: Set<String> = ["звук", "sound", "son", "окна", "вікна", "windows", "fenêtres", "dock"]

    /// The feature the request names, and whether it goes on or off: "выключи панду" → islandPanda off. Its name's every
    /// word must be there, endings aside; the longest name wins, so "звуки панды" is the panda's sounds, not the panda.
    static func feature(_ words: [String]) -> (id: String, on: Bool)? {
        let turnOff = off.any(words) || (words.contains("turn") && words.contains("off"))
        let turnOn = !turnOff && (on.any(words) || (words.contains("turn") && words.contains("on")))
        guard turnOn || turnOff else { return nil }
        var best: (id: String, length: Int)?
        for group in FeatureGroup.all {
            let candidates = [(group.main, [group.title, group.main.title])] + group.options.map { ($0, [$0.title]) }
            for (item, names) in candidates where !guarded.contains(item.id) {
                for name in names {
                    for language in Language.allCases {
                        let parts = PhotoWords.tokens(name.text(language)).filter { !filler.contains($0) }
                        if parts.count == 1, broad.contains(parts[0]) { continue }
                        guard !parts.isEmpty, parts.allSatisfy({ part in words.contains { matches($0, part) } }) else { continue }
                        let length = parts.reduce(0) { $0 + $1.count }
                        if length > (best?.length ?? 0) { best = (item.id, length) }
                    }
                }
            }
        }
        return best.map { ($0.id, turnOn) }
    }

    /// A word of the request against a word of a name, endings aside: "панду" is "панда", "песен" is "песни".
    private static func matches(_ word: String, _ part: String) -> Bool {
        let stem = String(part.prefix(max(3, part.count - 2)))
        return word == part || (word.hasPrefix(stem) && abs(word.count - part.count) <= 3)
    }

    // MARK: Automations

    private static let connect = Stems(prefixes: ["подключ", "підключ", "connect", "plug", "надева", "надяг", "вставл"])
    private static let disconnect = Stems(prefixes: ["отключ", "відключ", "disconnect", "unplug", "сним", "знім", "зня", "сня", "вынима", "вийма"])
    private static let headphones = Stems(prefixes: ["наушник", "навушник", "headphone", "earbud", "колонк", "speaker", "bluetooth", "блютуз"],
                                          whole: ["airpods"])
    private static let charger = Stems(prefixes: ["зарядк", "charger", "power", "адаптер"], whole: ["зарядку", "заряджання"])
    private static let battery = Stems(prefixes: ["батаре", "батар", "акумулятор", "battery", "заряд"])
    private static let below = Stems(prefixes: ["ниже", "меньше", "нижче", "менше", "below", "under", "упад", "опуст", "сяде"])
    private static let finished = Stems(prefixes: ["закончи", "заверш", "законч", "finish", "done", "готов", "доделал", "зробив"])
    private static let volume = Stems(prefixes: ["громкост", "гучніст", "volume"])
    private static let mics = Stems(prefixes: ["микрофон", "мікрофон", "mic"])
    private static let mute = Stems(prefixes: ["выключ", "заглуш", "отключ", "вимкн", "заглуш", "mute"])
    private static let output = Stems(prefixes: ["переключ", "перемкн", "switch", "выведи", "виведи"])
    private static let notice = Stems(prefixes: ["покажи", "сообщи", "уведом", "напомни", "скажи", "повідом", "нагадай", "notify", "show", "tell"])
    private static let play = Stems(prefixes: ["проиграй", "сыграй", "програй", "зіграй", "play", "пискни", "сигнал", "beep"])

    /// "When I connect AirPods, set the volume to 30%" as an automation, without a model: the trigger and steps people
    /// ask for most, in their words. Anything it can't place goes to the model, and either way the person sees the
    /// automation before it is made.
    static func automation(_ words: [String], _ text: String) -> JSONValue? {
        guard automationTopic.any(words) || cue.any(words) else { return nil }
        let lower = text.lowercased()
        // Each number by what it stands next to, so "в 9:00" never becomes a volume.
        let threshold = lower.firstMatch(of: #/(?:ниже|меньше|нижче|менше|below|under)\D{0,12}?(\d{1,2})/#).flatMap { Int($0.output.1) }
        let level = lower.firstMatch(of: #/(?:громкост|гучніст|volume)\D{0,24}?(\d{1,3})/#).flatMap { Int($0.output.1) }
            ?? lower.matches(of: #/(\d{1,3})\s*%/#).compactMap { Int($0.output.1) }.first { $0 != threshold }
        var trigger: [String: JSONValue]
        if agentNames.any(words) && finished.any(words) {
            trigger = ["kind": "agentFinished"]
        } else if battery.any(words) && below.any(words), let threshold, (1...99).contains(threshold) {
            trigger = ["kind": "batteryBelow", "number": .number(Double(threshold))]
        } else if headphones.any(words) && (connect.any(words) || disconnect.any(words)) {
            trigger = ["kind": disconnect.any(words) ? "deviceDisconnected" : "deviceConnected", "text": .string(words.contains("airpods") ? "AirPods" : "")]
        } else if charger.any(words) && (connect.any(words) || disconnect.any(words)) {
            trigger = ["kind": disconnect.any(words) ? "powerDisconnected" : "powerConnected"]
        } else if let time = text.firstMatch(of: #/(\d{1,2})[:.](\d{2})/#), let hour = Int(time.output.1), let minute = Int(time.output.2), hour < 24, minute < 60 {
            trigger = ["kind": "schedule", "number": .number(Double(hour * 60 + minute))]
        } else {
            return nil
        }
        var steps: [JSONValue] = []
        if volume.any(words), let level, (0...100).contains(level) {
            steps.append(["kind": "setVolume", "number": .number(Double(level))])
        }
        if mics.any(words) { steps.append(["kind": .string(mute.any(words) ? "muteMics" : "unmuteMics")]) }
        if output.any(words), headphones.any(words) || words.contains("звук") {
            steps.append(["kind": "switchOutput", "text": .string(words.contains("airpods") ? "AirPods" : "")])
        }
        if play.any(words) { steps.append(["kind": "sound", "text": "Glass"]) }
        if notice.any(words) {
            let quoted = text.firstMatch(of: #/[«"“](.+?)[»"”]/#).map { String($0.output.1) }
            steps.append(["kind": "notice", "text": .string(quoted ?? (trigger["kind"] == "agentFinished" ? "{agent} · {project}" : "{device}"))])
        }
        guard !steps.isEmpty else { return nil }
        // The person's own words name it, without "make an automation".
        var name = text.split(separator: ":", maxSplits: 1).last.map(String.init) ?? text
        name = name.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".,;:!?…")))
        name = String(name.prefix(80))
        return ["name": .string(name.prefix(1).uppercased() + name.dropFirst()), "trigger": .object(trigger), "steps": .array(steps)]
    }

    private static let automationTopic = Stems(prefixes: ["автоматиз", "automation", "сценари", "сценарі"])
    /// Words that say "whenever this happens" or "every day at".
    private static let cue = Stems(whole: ["когда", "коли", "when", "whenever", "каждый", "каждое", "каждую", "ежедневно", "щодня", "щоранку", "кожен",
                                           "кожного", "every", "daily"])
    private static let translate = Stems(prefixes: ["переведи", "переведите", "перевед", "переклад", "переклади", "translate"], whole: ["перевод"])

    /// The language a translation is asked into, by its name in the request: "на украинский", "англійською", "into French".
    private static let targets: [(stems: [String], name: String)] = [
        (["украин", "україн", "ukrain"], "Ukrainian"), (["англ", "english"], "English"), (["русск", "російськ", "russian"], "Russian"),
        (["француз", "french"], "French"), (["немец", "німецьк", "german"], "German"), (["испан", "іспанськ", "spanish"], "Spanish"),
        (["итальян", "італійськ", "italian"], "Italian"), (["польск", "польськ", "polish"], "Polish")
    ]

    /// A request's own instructions for the model: a translation is only the translation, named in English and in its
    /// own alphabet, whatever language SAVISUL speaks; a small model otherwise drifts into another script.
    static func instructions(for words: [String]) -> String? {
        guard translate.any(words) else { return nil }
        let target = targets.first { target in words.contains { word in target.stems.contains { word.hasPrefix($0) } } }?.name ?? "English"
        return "This request asks for a translation into \(target). Reply with the \(target) translation only, written entirely in the \(target) alphabet, without quotes or comments."
    }

    // MARK: Tools for the model

    private static let files = Stems(prefixes: ["файл", "папк", "folder", "file", "pdf", "загрузк", "завантаж", "download", "desktop", "документ", "document",
                                                "архив", "архів", "zip"], whole: ["тека", "теку", "теці", "теки", "теках", "стол", "стіл"])
    private static let find = Stems(prefixes: ["найд", "найт", "поищ", "покаж", "знайд", "шука", "пошук", "find", "search", "show", "list"],
                                    whole: ["где", "де", "where", "какие", "які", "сколько", "скільки"])
    private static let change = Stems(prefixes: ["перемест", "переимен", "скопир", "удал", "создай", "собер", "перенес", "переміст", "перейменуй",
                                                 "скопіюй", "видал", "створ", "збер", "move", "rename", "copy", "delete", "trash", "create", "collect", "make"])
    private static let read = Stems(prefixes: ["прочит", "прочт", "перескаж", "read", "summar"])
    private static let automation = Stems(prefixes: ["автоматиз", "automation", "сценари", "сценарі", "правил"], whole: ["когда", "коли", "when", "whenever"])
    private static let clipboard = Stems(prefixes: ["буфер", "clipboard", "скопиров", "скопіюв", "copied"])
    private static let images = Stems(prefixes: ["картинк", "изображ", "зображ", "png", "jpeg", "jpg", "heic", "конверт", "распозна", "розпізна",
                                                 "image", "convert", "screenshot", "скрин"])
    private static let shelf = Stems(prefixes: ["полк", "полиц", "полиц", "shelf"])
    private static let memory = Stems(prefixes: ["запомн", "запамят", "вспомн", "згадай", "забуд", "remember", "recall", "forget"])
    private static let notify = Stems(prefixes: ["островк", "острівц", "уведомлен", "сповіщ", "notif", "island"])
    private static let apps = Stems(prefixes: ["приложени", "застосунк", "процесс", "процес", "app", "process"])
    private static let features = Stems(prefixes: ["функци", "функці", "feature", "настройк", "налашту", "setting"])

    /// The tools a request's words point to: few enough for a small model to choose well. None leaves a plain answer.
    static func tools(for words: [String]) -> Set<String> {
        // An automation's words describe what it will do later, not what to do now: only its own tools.
        if automationTopic.any(words) { return ["automations.create", "automations.list", "automations.set_enabled", "automations.run"] }
        var tools = Set<String>()
        if files.any(words) {
            if change.any(words) {
                tools.formUnion(["files.move", "files.rename", "files.copy", "files.trash", "files.make_folder", "files.collect", "files.rename_by_date",
                                 "files.search", "files.list"])
            } else if read.any(words) {
                tools.formUnion(["files.read_text", "files.search", "files.list"])
            } else if sort.any(words) {
                tools.formUnion(["files.sort_folder", "files.list"])
            } else {
                tools.formUnion(["files.search", "files.list", "files.info", "files.large_files"])
            }
        }
        if automation.any(words) { tools.formUnion(["automations.create", "automations.list", "automations.set_enabled", "automations.run"]) }
        if clipboard.any(words) { tools.formUnion(["clipboard.search", "clipboard.copy"]) }
        if images.any(words) { tools.formUnion(["images.recognize_text", "images.convert", "photos.find"]) }
        if shelf.any(words) { tools.insert("shelf.add") }
        if memory.any(words) { tools.formUnion(["memory.remember", "memory.recall", "memory.forget"]) }
        if resources.any(words) || mac.any(words) || apps.any(words) { tools.formUnion(["mac.health", "mac.processes", "mac.apps", "mac.disks"]) }
        if meetings.any(words) { tools.insert("calendar.upcoming") }
        if agentNames.any(words) { tools.insert("agents.status") }
        if features.any(words) || on.any(words) || off.any(words) { tools.insert("savisul.feature") }
        if notify.any(words) { tools.insert("island.notify") }
        return tools
    }
}
#endif
