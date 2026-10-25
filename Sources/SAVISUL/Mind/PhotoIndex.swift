#if MOULD_ENGINE
import AppKit
import ImageIO
import Photos
import Vision

// MARK: The index

/// One picture SAVISUL has looked at: where it is, when it was taken, what Apple's Vision saw in it and the words on it.
/// The picture itself is never copied.
struct PhotoRecord: Codable, Hashable, Sendable {
    enum Source: String, Codable, Sendable { case file, library }

    var source: Source
    /// A file's path, or the Photos library's identifier for the item.
    var location: String
    var name: String
    var taken: Date?
    /// When the file or the library item last changed: a newer change is looked at again.
    var changed: Date
    /// Vision's labels ("cat", "beach", "receipt"…) and how sure it is of each, 0…1.
    var labels: [String: Float]
    /// Words read in the picture, for documents, receipts and screenshots.
    var text = ""
    var screenshot = false
    /// What the picture shows, as CLIP's vector (half precision, see PhotoMeaning), once that model is installed.
    var meaning: Data?

    var id: String { "\(source.rawValue):\(location)" }
    var date: Date { taken ?? changed }
}

/// The index SAVISUL keeps in Application Support: labels, a little text, dates and what each picture means, never the
/// pictures. Version 2 added the meaning; a version 1 index is read as it is, and its pictures gain it as they are looked
/// at again.
struct PhotoIndex: Codable, Sendable {
    var version = 2
    var records: [String: PhotoRecord] = [:]
    var updated: Date?

    static var location: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("SAVISUL/Photos/index.plist")
    }

    static func load(from url: URL) -> PhotoIndex {
        guard let data = try? Data(contentsOf: url), var index = try? PropertyListDecoder().decode(PhotoIndex.self, from: data),
              (1...2).contains(index.version) else {
            return PhotoIndex()
        }
        index.version = 2
        return index
    }

    func save(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}

/// What the person is looking for.
struct PhotoQuery: Sendable {
    /// Their own words, in any language.
    var words = ""
    /// What the picture shows, in plain English ("a cat sleeping on a sofa"), from a model.
    var scene = ""
    /// The meaning of what is asked for, as CLIP's vector of the scene: the search goes by meaning when it's there.
    var vector: [Float]?
    /// English names for what should be in the picture, from a model.
    var keywords: [String] = []
    /// Words written in the picture.
    var text = ""
    var after: Date?
    var before: Date?
    var limit = 24
}

struct PhotoMatch: Sendable {
    let record: PhotoRecord
    /// The labels and words it matched.
    let matched: [String]
    let score: Double
    /// Whether it surely shows what was asked for; a few that only come close are found when nothing is sure.
    var certain = true
}

extension PhotoIndex {
    /// Pictures that show what was asked for. With the meaning of the request (`query.vector`) each picture's own
    /// meaning decides, and Vision's labels and the words read in it only add to it; without it, Vision's labels decide.
    /// Either way a picture showing only part of what was asked for, or something else, is left out rather than shown:
    /// no answer is better than a wrong one.
    func search(_ query: PhotoQuery, now: Date = .now) -> [PhotoMatch] {
        let plan = PhotoWords.plan(query, now: now)
        let dated = records.values.filter { record in
            !(plan.after.map { record.date < $0 } ?? false) && !(plan.before.map { record.date >= $0 } ?? false)
        }
        // Only when: "photos from yesterday" are all of them, newest first.
        if plan.isEmpty && query.scene.isEmpty {
            guard plan.after != nil || plan.before != nil else { return [] }
            return dated.sorted { $0.date > $1.date }.prefix(max(1, query.limit)).map { PhotoMatch(record: $0, matched: [], score: 0) }
        }
        if let vector = query.vector { return Self.meaningful(dated, plan: plan, vector: vector, limit: query.limit) }
        return Self.labelled(dated, plan: plan, limit: query.limit)
    }

    /// By meaning: how alike each picture is to the request, a little more when Vision saw every thing asked for and for
    /// each word asked for that is written in it. Sure matches first; if none, at most four that come close, as maybes.
    private static func meaningful(_ records: [PhotoRecord], plan: PhotoWords.Plan, vector: [Float], limit: Int) -> [PhotoMatch] {
        var found: [PhotoMatch] = []
        for record in records {
            guard let meaning = record.meaning, !meaning.isEmpty else { continue }
            var score = PhotoMeaning.likeness(vector, meaning)
            var matched: [String] = []
            let seen = plan.concepts.compactMap { concept in
                concept.filter { (record.labels[$0] ?? 0) >= PhotoWords.sure }.max { (record.labels[$0] ?? 0) < (record.labels[$1] ?? 0) }
            }
            if !plan.concepts.isEmpty, seen.count == plan.concepts.count {
                score += PhotoWords.allSeen
                matched += seen
            }
            let text = PhotoWords.normalize(record.text), name = PhotoWords.normalize(record.name)
            for word in plan.written where text.contains(word) || name.contains(word) {
                score += PhotoWords.written
                matched.append("“\(word)”")
            }
            for word in plan.loose where word.count >= 4 && text.contains(PhotoWords.stem(word)) {
                score += PhotoWords.written / 2
                matched.append("“\(word)”")
            }
            found.append(PhotoMatch(record: record, matched: matched, score: Double(score), certain: score >= PhotoWords.certain))
        }
        found.sort { $0.score > $1.score }
        let sure = found.filter(\.certain)
        if !sure.isEmpty { return Array(sure.prefix(max(1, limit))) }
        return found.prefix(4).filter { $0.score >= Double(PhotoWords.close) }
    }

    /// By Vision's labels, while the meaning isn't there: a picture must show every thing asked for and carry every word
    /// asked to be written in it. Words nothing placed only count, among the words read on a picture.
    private static func labelled(_ records: [PhotoRecord], plan: PhotoWords.Plan, limit: Int) -> [PhotoMatch] {
        var found: [PhotoMatch] = []
        for record in records {
            var score = 0.0, matched: [String] = []
            var complete = true
            for concept in plan.concepts {
                let seen = concept.compactMap { label in record.labels[label].map { (label: label, confidence: $0) } }
                guard let best = seen.max(by: { $0.confidence < $1.confidence }), best.confidence >= PhotoWords.sure else {
                    complete = false
                    break
                }
                score += Double(best.confidence)
                matched.append(best.label)
            }
            guard complete else { continue }
            let text = PhotoWords.normalize(record.text), name = PhotoWords.normalize(record.name)
            guard plan.written.allSatisfy({ text.contains($0) || name.contains($0) }) else { continue }
            score += Double(plan.written.count)
            matched += plan.written.map { "“\($0)”" }
            let loose = plan.loose.filter { $0.count >= 4 && text.contains(PhotoWords.stem($0)) }
            if plan.concepts.isEmpty && plan.written.isEmpty && loose.isEmpty { continue }
            score += 0.5 * Double(loose.count)
            matched += loose.map { "“\($0)”" }
            found.append(PhotoMatch(record: record, matched: matched, score: score))
        }
        found.sort { abs($0.score - $1.score) > 0.05 ? $0.score > $1.score : $0.record.date > $1.record.date }
        return Array(found.prefix(max(1, limit)))
    }
}

// MARK: Words

/// How the person's words become Vision's labels: English directly, Russian and Ukrainian through everyday stems, and
/// dates from words like "yesterday", "in May" or "2024". A model on this Mac usually hands over English keywords as
/// well; these words are what still works without one.
enum PhotoWords {
    /// Below this Vision is guessing.
    static let sure: Float = 0.15
    /// A picture alike to the request by at least this much shows it. Measured on a thousand photographs (COCO, with
    /// fifty requests in Russian, some for things that aren't there): nine in ten pictures shown are right, and a thing
    /// that isn't there gets no answer.
    static let certain: Float = 0.245
    /// Close enough to offer a few as maybes when nothing is sure.
    static let close: Float = 0.215
    /// Added when Vision saw every thing asked for.
    static let allSeen: Float = 0.03
    /// Added for each word asked for that is written in the picture.
    static let written: Float = 0.06

    /// Endings vary, the start of a word doesn't: "паролем" finds "пароль".
    static func stem(_ word: String) -> String {
        word.count > 5 ? String(word.prefix(word.count - 2)) : word
    }

    struct Plan {
        /// Each one a thing to see: any of its labels shows it.
        var concepts: [[String]] = []
        /// Words that must be written in the picture or its name.
        var written: [String] = []
        /// Words nothing else placed: looked for in the picture's text and name.
        var loose: [String] = []
        var after: Date?
        var before: Date?

        var isEmpty: Bool { concepts.isEmpty && written.isEmpty && loose.isEmpty }
    }

    /// Every label Vision can give.
    static let vocabulary: Set<String> = Set((try? VNClassifyImageRequest().supportedIdentifiers()) ?? [])

    static func plan(_ query: PhotoQuery, now: Date) -> Plan {
        var plan = Plan()
        var seen = Set<[String]>()
        func add(_ labels: [String]) {
            let known = labels.filter { vocabulary.isEmpty || vocabulary.contains($0) }
            if !known.isEmpty, seen.insert(known.sorted()).inserted { plan.concepts.append(known) }
        }
        for keyword in query.keywords {
            let labels = english(keyword)
            if labels.isEmpty {
                let word = normalize(keyword)
                if word.count >= 3, !plan.loose.contains(word) { plan.loose.append(word) }
            } else {
                add(labels)
            }
        }
        for word in tokens(query.words) where !isStop(word) && !isDate(word) {
            if let labels = native(word) {
                add(labels)
            } else if word.unicodeScalars.allSatisfy(\.isASCII), case let labels = english(word), !labels.isEmpty {
                add(labels)
            } else if word.count >= 3, !plan.loose.contains(word) {
                plan.loose.append(word)
            }
        }
        plan.written = tokens(query.text).filter { $0.count >= 2 }
        if query.after != nil || query.before != nil {
            plan.after = query.after
            plan.before = query.before
        } else {
            (plan.after, plan.before) = dates(in: query.words, now: now)
        }
        return plan
    }

    /// Lowercase letters and digits only: "Ёлка’s" → "елкаs", so endings and apostrophes never get in the way.
    static func normalize(_ text: String) -> String {
        var result = ""
        for character in text.lowercased() {
            switch character {
            case "ё": result.append("е")
            case "'", "’", "ʼ", "`": continue
            default: result.append(character.isLetter || character.isNumber ? character : " ")
            }
        }
        return result
    }

    static func tokens(_ text: String) -> [String] {
        normalize(text).split(separator: " ").map(String.init)
    }

    // MARK: English

    /// Labels for an English word: Vision's own word for it, the label itself, or labels made of it ("cake" →
    /// "birthday_cake").
    static func english(_ raw: String) -> [String] {
        let word = raw.lowercased().trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " ", with: "_")
        guard word.count >= 2 else { return [] }
        var forms = [word]
        if word.hasSuffix("ies") { forms.append(String(word.dropLast(3)) + "y") }
        if word.hasSuffix("es") { forms.append(String(word.dropLast(2))) }
        if word.hasSuffix("s") { forms.append(String(word.dropLast())) }
        var labels = Set<String>()
        for form in forms {
            if let named = synonyms[form] {
                labels.formUnion(named)
            } else {
                labels.formUnion(vocabulary.filter { $0 == form || $0.split(separator: "_").contains(Substring(form)) })
            }
        }
        return labels.sorted()
    }

    /// English words Vision says otherwise.
    static let synonyms: [String: [String]] = [
        "sea": ["ocean", "beach", "shore", "water_body"], "seaside": ["ocean", "beach", "shore"], "coast": ["shore", "beach", "ocean"],
        "kitten": ["kitten", "cat"], "kitty": ["kitten", "cat"], "puppy": ["dog"], "doggy": ["dog"],
        "kid": ["child"], "children": ["child", "baby"], "toddler": ["child", "baby"],
        "person": ["people", "adult"], "man": ["people", "adult"], "woman": ["people", "adult"], "human": ["people", "adult"],
        "friend": ["people", "adult"], "family": ["people", "child"], "selfie": ["people", "adult"], "portrait": ["people", "adult"],
        "face": ["people", "adult"], "group": ["people", "crowd"],
        "car": ["car", "automobile"], "plane": ["airplane"], "aeroplane": ["airplane"], "bike": ["bicycle", "motorcycle"], "motorbike": ["motorcycle"],
        "text": ["document", "handwriting", "receipt", "screenshot"], "paper": ["document"], "check": ["receipt"], "bill": ["receipt"],
        "invoice": ["document", "receipt"], "note": ["handwriting", "document"],
        "meal": ["food"], "dish": ["food"], "lunch": ["food"], "dinner": ["food"], "breakfast": ["food"],
        "town": ["cityscape", "street", "building"], "city": ["cityscape", "street", "building", "skyscraper"],
        "home": ["house_single", "building", "interior_room"], "house": ["house_single", "building"],
        "sunset": ["sunset_sunrise"], "sunrise": ["sunset_sunrise"], "dawn": ["sunset_sunrise"], "night": ["night_sky"], "stars": ["night_sky"],
        "christmas": ["christmas_tree", "christmas_decoration"], "couch": ["sofa"], "tv": ["television"],
        "snowy": ["snow"], "pet": ["cat", "dog"], "animals": ["animal", "mammal"]
    ]

    // MARK: Russian and Ukrainian

    /// Everyday things to look for, by Russian and Ukrainian stems ("=" marks a whole word), with Vision's labels for them.
    static let concepts: [(stems: [String], labels: [String])] = [
        (["кот", "котик", "котен", "котят", "кошк", "кошек", "кошеч", "кіт", "кішк", "кошен"], ["cat", "kitten", "adult_cat"]),
        (["собак", "собач", "щен", "щенк", "щенок", "=пес", "=пса", "=псом", "=псы", "=псов", "=псу", "=песик", "=песика", "=цуцик", "цуценя"], ["dog"]),
        (["птиц", "птах", "пташ"], ["bird"]),
        (["пляж"], ["beach", "shore", "sand"]),
        (["=море", "=моря", "=морем", "=морю", "=морі", "морск", "морськ", "океан"], ["ocean", "beach", "shore", "water_body"]),
        (["=гора", "=горы", "=горах", "=горе", "=гору", "=гори", "горн", "гірськ", "гірн"], ["mountain"]),
        (["снег", "снеж", "сніг", "сніж"], ["snow"]),
        (["машин", "автомобил", "=авто", "автівк", "тачк"], ["car", "automobile"]),
        (["=еда", "=еды", "=еду", "=едой", "=їжа", "=їжі", "=їжу", "блюд", "страв"], ["food"]),
        (["торт"], ["cake", "birthday_cake", "wedding_cake", "cake_regular"]),
        (["цвет", "цветоч", "цветочк", "квіт", "квітк"], ["flower", "flower_arrangement"]),
        (["дерев", "деревь"], ["tree"]),
        (["елк", "елочк", "ялин"], ["christmas_tree", "christmas_decoration"]),
        (["закат", "рассвет", "світан", "=захід", "=заходу"], ["sunset_sunrise"]),
        (["=небо", "=небе", "=неба", "=небі"], ["sky", "blue_sky"]),
        (["город", "=місто", "=міста", "=місті", "=містом"], ["cityscape", "street", "building", "skyscraper"]),
        (["здани", "будин", "будинк", "будівл", "небоскреб", "хмарочос"], ["building", "skyscraper"]),
        (["документ", "бумаг", "папер", "справк", "довідк", "паспорт"], ["document"]),
        (["чек", "квитанци", "квитанці"], ["receipt"]),
        (["скрин", "скриншот", "скріншот"], ["screenshot"]),
        (["люд", "человек", "людин", "селфи", "селфі", "портрет", "друз", "друзь", "друж"], ["people", "adult", "crowd"]),
        (["ребен", "=дети", "=детей", "=детьми", "детск", "малыш", "дитин", "=діти", "=дітей", "=дітьми", "дитяч"], ["child", "baby"]),
        (["младен", "немовл"], ["baby"]),
        (["лошад", "=конь", "=коня", "=конем", "=кінь", "=коні", "коник"], ["horse"]),
        (["компьютер", "компютер", "ноутбук", "=ноут", "макбук"], ["computer", "laptop", "computer_monitor", "computer_keyboard"]),
        (["телефон", "смартфон", "айфон"], ["phone"]),
        (["книг", "книж", "книжк"], ["book"]),
        (["=вода", "=воды", "=воде", "=воду", "=водой", "=води", "=воді"], ["water", "water_body"]),
        (["=лес", "=леса", "=лесу", "=лесом", "лесн", "=ліс", "=лісі", "=лісу", "лісов"], ["forest"]),
        (["=река", "=реки", "=реке", "=реку", "=рекой", "річк"], ["river"]),
        (["озер"], ["lake"]),
        (["лодк", "лодоч", "катер", "яхт", "човн", "човен", "корабл", "корабел"], ["boat", "cruise_ship"]),
        (["самолет", "літак"], ["airplane"]),
        (["велосипед"], ["bicycle"]),
        (["мотоцикл", "байк"], ["motorcycle"]),
        (["пицц", "піц"], ["pizza"]),
        (["кофе", "кофей", "=кава", "=каву", "=кави", "=кавою"], ["coffee"]),
        (["напит", "напитк", "напій", "напо", "коктейл"], ["drink"]),
        (["десерт", "сладост", "солодощ", "пирожн", "тістеч"], ["dessert", "cake"]),
        (["фрукт", "яблок", "яблук", "банан"], ["fruit"]),
        (["спорт"], ["sport"]),
        (["мяч"], ["ball"]),
        (["концерт"], ["concert"]),
        (["свадьб", "весілл"], ["wedding", "wedding_dress", "wedding_cake"]),
        (["рожден", "народжен"], ["birthday_cake", "balloon", "gift"]),
        (["новогод", "новоріч", "рождеств", "рождественск", "різдв", "різдвян"], ["christmas_tree", "christmas_decoration", "fireworks"]),
        (["одежд", "одяг", "плать", "сукн", "куртк"], ["clothing"]),
        (["обув", "кроссов", "кроссовк", "кросів", "кросовк", "туфл", "взутт", "ботин", "черевик"], ["shoes"]),
        (["=карта", "=карту", "=карты", "=карте", "=мапа", "=мапу", "=мапи"], ["map"]),
        (["график", "графік", "диаграм", "диаграмм", "діаграм", "схем"], ["chart", "diagram"]),
        (["рукопис", "почерк", "записк", "конспект", "нотатк", "заметк"], ["handwriting", "document"]),
        (["доск", "дошк"], ["whiteboard"]),
        (["вывеск", "табличк", "вивіск", "=знак", "=знаки"], ["sign", "street_sign"]),
        (["ноч", "ніч", "звезд", "зірк"], ["night_sky"]),
        (["=луна", "=луну", "=луной", "=луны"], ["moon"]),
        (["солнц", "сонц"], ["sun", "sunset_sunrise"]),
        (["радуг", "=веселка", "=веселку", "=веселки"], ["rainbow"]),
        (["салют", "феєрвер", "фейерверк"], ["fireworks"]),
        (["огон", "=огня", "=огнем", "костер", "костр", "вогн", "вогон", "багатт"], ["fire"]),
        (["палатк", "намет", "поход", "похід", "кемпинг", "кемпінг"], ["tent", "camping", "hiking"]),
        (["пустын", "пустел"], ["desert"]),
        (["водопад", "водоспад"], ["waterfall"]),
        (["=мост", "=моста", "=мосту", "=мостом", "=міст", "=мости"], ["bridge"]),
        (["дорог", "дорож", "шоссе", "трас"], ["road", "street"]),
        (["улиц", "вулиц"], ["street"]),
        (["поезд", "потяг", "электрич", "електрич", "вокзал"], ["train", "train_real", "train_station"]),
        (["автобус"], ["bus"]),
        (["грузовик", "вантаж"], ["truck", "semi_truck"]),
        (["кухн"], ["kitchen", "kitchen_room"]),
        (["спальн"], ["bedroom"]),
        (["комнат", "кімнат", "интерьер", "інтер"], ["interior_room", "living_room", "bedroom"]),
        (["животн", "тварин", "зверь", "звер", "звір"], ["animal", "mammal"]),
        (["насеком", "комах"], ["insect", "butterfly", "bee"]),
        (["бабочк", "метелик"], ["butterfly"]),
        (["рыб", "риб"], ["fish"]),
        (["медвед", "ведмед"], ["bear"]),
        (["слон"], ["elephant"]),
        (["жираф"], ["giraffe"]),
        (["=лев", "=льва", "=львом", "=льви", "=левы"], ["lion"]),
        (["тигр"], ["tiger"]),
        (["обезьян", "мавп"], ["monkey"]),
        (["=лиса", "=лису", "=лисы", "лисиц"], ["fox"]),
        (["белк", "білк"], ["squirrel"]),
        (["кролик", "заяц", "зайц", "кріл", "заєць", "зайч"], ["rabbit"]),
        (["коров"], ["cow"]),
        (["свин", "свинь"], ["pig"]),
        (["овц", "овеч", "вівц", "барашк", "баран"], ["sheep"]),
        (["утк", "уточ", "качк", "качен"], ["duck"]),
        (["=сова", "=сову", "=совы", "=сови", "совен"], ["owl"]),
        (["=орел", "=орла", "=орлом", "=орли", "=орлы"], ["eagle"]),
        (["попуга", "папуг"], ["parrot"]),
        (["пингвин", "пінгвін"], ["penguin"]),
        (["зебр"], ["zebra"]),
        (["гитар", "гітар"], ["guitar"]),
        (["пианин", "рояль", "фортепиан", "піаніно", "фортепіано"], ["piano"]),
        (["шарик", "=шары", "повітрян", "воздушн"], ["balloon"]),
        (["подар", "подарк"], ["gift"]),
        (["игрушк", "іграшк"], ["toy", "stuffed_animals", "doll"]),
        (["бассейн", "басейн"], ["pool", "swimming"]),
        (["футбол"], ["soccer", "football"]),
        (["баскетбол"], ["basketball"]),
        (["теннис", "теніс"], ["tennis"]),
        (["лыж", "лиж"], ["skiing", "ski_equipment"]),
        (["хлеб", "хліб"], ["bread"]),
        (["=вино", "=вина", "=вином", "винн"], ["wine", "red_wine", "white_wine", "sparkling_wine"]),
        (["пив"], ["beer"]),
        (["суши", "суші", "ролл"], ["sushi"]),
        (["салат"], ["salad"]),
        (["=суп", "=супа", "=супом", "супчик"], ["soup"]),
        (["морожен", "морозив"], ["ice_cream"]),
        (["мяс"], ["meat"]),
        (["бургер", "гамбургер"], ["burger"]),
        (["бутерброд", "сэндвич", "сендвіч"], ["sandwich"]),
        (["шоколад"], ["chocolate"]),
        (["свеч", "свіч"], ["candle"]),
        (["диван"], ["sofa"]),
        (["кроват", "ліжк"], ["bed"]),
        (["песок", "=песка", "=песке", "пісок", "=піску"], ["sand", "sand_dune", "beach"]),
        (["трав", "газон"], ["grass"]),
        (["=сад", "=саду", "=сада", "садик"], ["garden"]),
        (["парк"], ["park"]),
        (["стадион", "стадіон"], ["stadium"]),
        (["музе"], ["museum"])
    ]

    /// The labels for a Russian or Ukrainian word, from the stem it starts with: "котиком" → cat. A stem takes at
    /// most three more letters, an ending's length, so "котлета" is never a cat.
    static func native(_ word: String) -> [String]? {
        var best: (length: Int, labels: [String])?
        for concept in concepts {
            for stem in concept.stems {
                let exact = stem.hasPrefix("=")
                let core = exact ? String(stem.dropFirst()) : stem
                let fits = exact ? word == core : word.hasPrefix(core) && word.count - core.count <= 3
                if fits, core.count > (best?.length ?? 0) { best = (core.count, concept.labels) }
            }
        }
        return best?.labels
    }

    /// Words that ask for a picture rather than say what is in it.
    static let stop: Set<String> = [
        "найди", "найти", "найдите", "покажи", "покажите", "поищи", "ищу", "ищи", "где", "мне", "мой", "моя", "мои", "мое", "моих", "все", "фото",
        "снимок", "снимки", "снимков", "на", "в", "во", "с", "со", "и", "или", "а", "есть", "был", "была", "были", "это", "этот", "эта", "эти",
        "тот", "та", "те", "там", "тут", "как", "из", "у", "по", "за", "к", "о", "об", "про", "для", "от", "до", "без", "какой", "какая",
        "знайди", "знайти", "пошукай", "шукаю", "шукай", "де", "мені", "мій", "мої", "моє", "всі", "знімок", "знімки", "з", "із",
        "зі", "й", "або", "є", "був", "була", "були", "це", "цей", "ця", "ці", "той", "ті", "як", "від", "який", "яка", "яке", "які",
        "find", "show", "search", "me", "my", "a", "an", "the", "of", "with", "on", "in", "at", "from", "photo", "photos", "picture", "pictures",
        "pic", "pics", "image", "images", "where", "is", "are", "was", "were", "some", "any", "all", "that", "which", "this", "these", "those",
        "for", "and", "or", "to", "please", "пожалуйста", "будь", "ласка"
    ]

    private static let stopStems = ["фотк", "фотограф", "картинк", "изображ", "зображ", "світлин", "котор", "котр"]

    static func isStop(_ word: String) -> Bool {
        word.count < 2 || stop.contains(word) || stopStems.contains { word.hasPrefix($0) }
    }

    // MARK: Dates

    private static let months: [[String]] = [
        ["январ", "=січень", "=січня", "=січні", "january", "jan"], ["феврал", "=лютий", "=лютого", "=лютому", "february", "feb"],
        ["=март", "=марта", "=марте", "=березень", "=березня", "=березні", "march"], ["апрел", "=квітень", "=квітня", "=квітні", "april"],
        ["=май", "=мая", "=мае", "=травень", "=травня", "=травні", "may"], ["июн", "=червень", "=червня", "=червні", "june"],
        ["июл", "=липень", "=липня", "=липні", "july"], ["август", "=серпень", "=серпня", "=серпні", "august"],
        ["сентябр", "=вересень", "=вересня", "=вересні", "september"], ["октябр", "=жовтень", "=жовтня", "=жовтні", "october"],
        ["ноябр", "=листопад", "=листопада", "=листопаді", "november"], ["декабр", "=грудень", "=грудня", "=грудні", "december"]
    ]
    /// The months a season starts at, and its words.
    private static let seasons: [(start: Int, words: Set<String>)] = [
        (12, ["зима", "зимой", "зиму", "зимы", "зиме", "взимку", "зимою", "зими", "зимі", "winter"]),
        (3, ["весна", "весной", "весну", "весны", "весне", "навесні", "весною", "весни", "весні", "spring"]),
        (6, ["лето", "летом", "лета", "лете", "літо", "влітку", "літом", "літа", "літі", "summer"]),
        (9, ["осень", "осенью", "осени", "осінь", "восени", "осені", "autumn", "fall"])
    ]
    private static let today: Set<String> = ["сегодня", "сьогодні", "today"]
    private static let yesterday: Set<String> = ["вчера", "вчора", "yesterday"]
    private static let earlier: Set<String> = ["last", "previous", "ago", "назад", "тому"]
    private static let this: Set<String> = ["этом", "этой", "этот", "эту", "цьому", "цій", "цей", "цю", "this"]

    private static func matches(_ word: String, _ forms: [String]) -> Bool {
        forms.contains { $0.hasPrefix("=") ? word == $0.dropFirst() : word.hasPrefix($0) }
    }

    private static func isWeek(_ word: String) -> Bool { word.hasPrefix("недел") || word.hasPrefix("тижн") || word == "тиждень" || word == "week" }
    private static func isMonth(_ word: String) -> Bool { word.hasPrefix("месяц") || word.hasPrefix("місяц") || word == "month" }
    private static func isYear(_ word: String) -> Bool { ["год", "году", "года", "рік", "році", "року", "year"].contains(word) }
    private static func isPrevious(_ word: String) -> Bool { word.hasPrefix("прошл") || word.hasPrefix("минул") || earlier.contains(word) }

    /// A word that only says when.
    static func isDate(_ word: String) -> Bool {
        if let year = Int(word), (1990...2100).contains(year) { return true }
        return today.contains(word) || yesterday.contains(word) || this.contains(word) || isPrevious(word) || isWeek(word) || isMonth(word) || isYear(word)
            || months.contains { matches(word, $0) } || seasons.contains { $0.words.contains(word) }
    }

    /// The span of time the words name, if they name one: [after, before).
    static func dates(in text: String, now: Date) -> (Date?, Date?) {
        let words = tokens(text)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        calendar.firstWeekday = 2
        let day = calendar.startOfDay(for: now)
        func shift(_ date: Date, _ component: Calendar.Component, _ value: Int) -> Date { calendar.date(byAdding: component, value: value, to: date) ?? date }
        func start(_ year: Int, _ month: Int) -> Date { calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? now }
        let year = words.compactMap { Int($0) }.first { (1990...2100).contains($0) }
        let previous = words.contains(where: isPrevious)
        let current = words.contains { this.contains($0) }
        let nowYear = calendar.component(.year, from: now), nowMonth = calendar.component(.month, from: now)

        if words.contains(where: today.contains) { return (day, shift(day, .day, 1)) }
        if words.contains(where: yesterday.contains) { return (shift(day, .day, -1), day) }
        if words.contains(where: { $0 == "позавчера" || $0 == "позавчора" }) { return (shift(day, .day, -2), shift(day, .day, -1)) }
        if words.contains(where: isWeek) {
            let week = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? day
            if previous { return (shift(week, .day, -7), week) }
            return current ? (week, shift(day, .day, 1)) : (shift(day, .day, -7), shift(day, .day, 1))
        }
        if let index = months.firstIndex(where: { forms in words.contains { matches($0, forms) } }) {
            let month = index + 1
            let chosen = year ?? (month > nowMonth ? nowYear - 1 : nowYear)
            return (start(chosen, month), shift(start(chosen, month), .month, 1))
        }
        if words.contains(where: isMonth) {
            let month = start(nowYear, nowMonth)
            if previous { return (shift(month, .month, -1), month) }
            return current ? (month, shift(month, .month, 1)) : (shift(day, .day, -31), shift(day, .day, 1))
        }
        if let season = seasons.first(where: { season in words.contains { season.words.contains($0) } }) {
            // The latest such season that has begun; winter counts from its December.
            var chosen = year.map { season.start == 12 ? $0 - 1 : $0 } ?? nowYear
            if year == nil && start(chosen, season.start) > now { chosen -= 1 }
            if year == nil && previous { chosen -= 1 }
            let from = start(chosen, season.start)
            return (from, shift(from, .month, 3))
        }
        if let year { return (start(year, 1), start(year + 1, 1)) }
        if words.contains(where: isYear) {
            if previous { return (start(nowYear - 1, 1), start(nowYear, 1)) }
            if current { return (start(nowYear, 1), start(nowYear + 1, 1)) }
        }
        return (nil, nil)
    }
}

// MARK: Looking at pictures

/// Reads pictures for the index: files in the assistant's folders and, when the person allowed it, the Photos library.
/// Each one is read as a small thumbnail and looked at with Vision, on this Mac.
enum PhotoIndexer {
    struct Item: Sendable {
        let source: PhotoRecord.Source
        let location: String
        let name: String
        let taken: Date?
        let changed: Date
        let screenshot: Bool

        var id: String { "\(source.rawValue):\(location)" }
    }

    static let extensions: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "gif", "webp", "bmp"]
    /// Years of photos fit; a folder of a million icons doesn't stall the Mac.
    static let limit = 40_000
    private static let skipped: Set<String> = ["node_modules", "Library", "DerivedData", "build", "Pods"]

    /// Pictures in the folders and below them, in the folders' order.
    static func files(in folders: [URL]) -> [Item] {
        var items: [Item] = []
        var seen = Set<String>()
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .contentModificationDateKey, .fileSizeKey]
        for folder in folders {
            guard let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            while let url = walker.nextObject() as? URL {
                guard items.count < limit else { return items }
                let values = try? url.resourceValues(forKeys: Set(keys))
                if values?.isDirectory == true {
                    if skipped.contains(url.lastPathComponent) { walker.skipDescendants() }
                    continue
                }
                // Icons and tiny bits of interface aren't what anyone looks for.
                guard values?.isRegularFile == true, extensions.contains(url.pathExtension.lowercased()), (values?.fileSize ?? 0) >= 8_000 else { continue }
                let path = url.standardizedFileURL.path
                guard seen.insert(path).inserted else { continue }
                let name = url.lastPathComponent
                let words = PhotoWords.normalize(name)
                let screenshot = ["screenshot", "screen shot", "снимок экрана", "знімок екрана", "скриншот"].contains { words.contains($0) }
                items.append(Item(source: .file, location: path, name: name, taken: nil, changed: values?.contentModificationDate ?? .distantPast,
                                  screenshot: screenshot))
            }
        }
        return items
    }

    /// The Photos library's pictures, newest first; empty unless the person allowed SAVISUL to see them.
    static func library() -> [Item] {
        guard PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized else { return [] }
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = limit
        let assets = PHAsset.fetchAssets(with: .image, options: options)
        var items: [Item] = []
        items.reserveCapacity(assets.count)
        assets.enumerateObjects { asset, _, _ in
            items.append(Item(source: .library, location: asset.localIdentifier, name: "", taken: asset.creationDate,
                              changed: asset.modificationDate ?? asset.creationDate ?? .distantPast, screenshot: asset.mediaSubtypes.contains(.photoScreenshot)))
        }
        return items
    }

    /// Looks at one picture: what is in it, what it means (with `meaning`) and, for documents, receipts and screenshots,
    /// the words on it. One that can't be read is still remembered, without labels, so it isn't tried again until it
    /// changes.
    static func look(at item: Item, meaning: PhotoMeaning? = nil) -> PhotoRecord {
        var record = PhotoRecord(source: item.source, location: item.location, name: item.name, taken: item.taken, changed: item.changed, labels: [:],
                                 screenshot: item.screenshot)
        let small: CGImage?
        let large: () -> CGImage?
        switch item.source {
        case .file:
            guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: item.location) as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else {
                return record
            }
            record.taken = taken(source)
            small = thumbnail(source, size: 512)
            large = { thumbnail(source, size: 1600) }
        case .library:
            guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [item.location], options: nil).firstObject else { return record }
            record.name = PHAssetResource.assetResources(for: asset).first?.originalFilename ?? ""
            small = picture(asset, size: 512)
            large = { picture(asset, size: 1600) }
        }
        guard let small, small.width >= 48, small.height >= 48 else { return record }
        record.labels = classify(small)
        record.meaning = meaning?.vector(of: small).map(PhotoMeaning.pack)
        if record.screenshot { record.labels["screenshot"] = 1 }
        if record.screenshot || texty(record.labels) { record.text = read(large() ?? small) }
        return record
    }

    /// A picture looked at before the meaning was installed gains it, and keeps what Vision saw.
    static func mean(_ record: PhotoRecord, meaning: PhotoMeaning) -> PhotoRecord {
        var record = record
        let small: CGImage?
        switch record.source {
        case .file:
            small = CGImageSourceCreateWithURL(URL(fileURLWithPath: record.location) as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
                .flatMap { thumbnail($0, size: 512) }
        case .library:
            small = PHAsset.fetchAssets(withLocalIdentifiers: [record.location], options: nil).firstObject.flatMap { picture($0, size: 512) }
        }
        // One that can't be read is given an empty meaning, so it isn't tried again on every update.
        record.meaning = small.flatMap(meaning.vector(of:)).map(PhotoMeaning.pack) ?? Data()
        return record
    }

    private static func thumbnail(_ source: CGImageSource, size: Int) -> CGImage? {
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceThumbnailMaxPixelSize: size, kCGImageSourceShouldCacheImmediately: true]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private static let exif: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter
    }()

    /// When the camera took it, from the picture's own data.
    private static func taken(_ source: CGImageSource) -> Date? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return nil }
        let original = (properties[kCGImagePropertyExifDictionary] as? [CFString: Any])?[kCGImagePropertyExifDateTimeOriginal] as? String
        let tiff = (properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any])?[kCGImagePropertyTIFFDateTime] as? String
        return (original ?? tiff).flatMap(exif.date(from:))
    }

    /// A library picture as it is on this Mac: nothing is downloaded from iCloud to index it.
    private static func picture(_ asset: PHAsset, size: CGFloat) -> CGImage? {
        let options = PHImageRequestOptions()
        options.isSynchronous = true
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = false
        var result: CGImage?
        PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: size, height: size), contentMode: .aspectFit, options: options) { image, _ in
            result = image.flatMap(ImageWork.cgImage)
        }
        return result
    }

    private static func classify(_ image: CGImage) -> [String: Float] {
        let request = VNClassifyImageRequest()
        try? VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        var labels: [String: Float] = [:]
        for observation in (request.results ?? []).sorted(by: { $0.confidence > $1.confidence }).prefix(24) where observation.confidence >= 0.1 {
            labels[observation.identifier] = (observation.confidence * 100).rounded() / 100
        }
        return labels
    }

    private static let textLabels: Set<String> = ["document", "receipt", "screenshot", "handwriting", "whiteboard", "sign", "street_sign", "chart", "diagram",
                                                  "map", "book", "illustrations", "computer_monitor", "laptop", "television"]

    private static func texty(_ labels: [String: Float]) -> Bool {
        labels.contains { textLabels.contains($0.key) && $0.value >= 0.2 }
    }

    /// Cyrillic needs Vision's accurate reading; only pictures that look like text get it.
    private static func read(_ image: CGImage) -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        let supported = (try? request.supportedRecognitionLanguages()) ?? []
        request.recognitionLanguages = ["ru-RU", "uk-UA", "en-US"].filter(supported.contains)
        try? VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
        return String(text.prefix(600))
    }
}
#endif
