#if MOULD_ENGINE
import AppKit
import Foundation
import Testing
@testable import SAVISUL

/// Finding a picture by what is in it: words to labels, dates, and a real index of pictures that come with macOS, in a
/// temporary folder. The Photos library is never touched.
@Suite(.serialized)
@MainActor
final class PhotoSearchTests {
    let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("savisul-photos-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    private func concepts(_ words: String, keywords: [String] = []) -> [[String]] {
        var query = PhotoQuery()
        query.words = words
        query.keywords = keywords
        return PhotoWords.plan(query, now: .now).concepts
    }

    @Test func wordsInThreeLanguagesBecomeVisionLabels() {
        #expect(concepts("Найди фото кота на диване").contains { $0.contains("cat") })
        #expect(concepts("Найди фото кота на диване").contains { $0.contains("sofa") })
        #expect(concepts("знайди фото котиків").contains { $0.contains("cat") })
        #expect(concepts("photos of cats on the beach").contains { $0.contains("beach") })
        #expect(concepts("собакой у моря").contains { $0.contains("dog") })
        #expect(concepts("собакой у моря").contains { $0.contains("ocean") })
        // An ending is at most three letters: a cutlet is not a cat, a big cathedral is not a bicycle.
        #expect(!concepts("котлета").contains { $0.contains("cat") })
        #expect(concepts("великий собор").isEmpty)
        // A model's English keywords count as well.
        #expect(concepts("фото", keywords: ["giraffe"]).contains { $0.contains("giraffe") })
    }

    @Test func datesComeFromWords() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 12)))
        func day(_ year: Int, _ month: Int, _ day: Int = 1) -> Date? { calendar.date(from: DateComponents(year: year, month: month, day: day)) }
        func span(_ text: String) -> (Date?, Date?) { PhotoWords.dates(in: text, now: now) }

        #expect(span("вчера") == (day(2026, 10, 24), day(2026, 10, 25)))
        #expect(span("фото в мае") == (day(2026, 5), day(2026, 6)))
        #expect(span("в декабре") == (day(2025, 12), day(2026, 1)))
        #expect(span("у грудні 2024") == (day(2024, 12), day(2025, 1)))
        #expect(span("летом") == (day(2026, 6), day(2026, 9)))
        #expect(span("прошлым летом") == (day(2025, 6), day(2025, 9)))
        #expect(span("зимой") == (day(2025, 12), day(2026, 3)))
        #expect(span("минулого місяця") == (day(2026, 9), day(2026, 10)))
        #expect(span("на прошлой неделе") == (day(2026, 10, 12), day(2026, 10, 19)))
        #expect(span("в 2024") == (day(2024, 1), day(2025, 1)))
        #expect(span("кот на диване") == (nil, nil))
        // A month's name is a date, not a thing: April isn't flowers, May isn't grass.
        #expect(concepts("у квітні").isEmpty)
        #expect(concepts("у травні").isEmpty)
    }

    @Test func onlyPlainPhotoRequestsSkipTheModel() {
        #expect(PhotoSearch.isPhotoRequest("Найди фото кота на диване"))
        #expect(PhotoSearch.isPhotoRequest("знайди фото з моря"))
        #expect(PhotoSearch.isPhotoRequest("Where is the screenshot with the address?"))
        #expect(PhotoSearch.isPhotoRequest("покажи скрин с паролем"))
        #expect(!PhotoSearch.isPhotoRequest("Найди фото кота и положи на полку"))
        #expect(!PhotoSearch.isPhotoRequest("Разбери Загрузки"))
        #expect(!PhotoSearch.isPhotoRequest("покажи погоду"))
    }

    @Test func picturesAreFoundByWhatIsInThem() async throws {
        let samples = URL(fileURLWithPath: "/Library/User Pictures")
        var copied = 0
        for folder in ["Animals", "Flowers"] {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: samples.appendingPathComponent(folder).path)) ?? []
            for name in names where name.hasSuffix(".heic") {
                let source = samples.appendingPathComponent(folder).appendingPathComponent(name).resolvingSymlinksInPath()
                try FileManager.default.copyItem(at: source, to: directory.appendingPathComponent(name))
                copied += 1
            }
        }
        try #require(copied >= 6, "macOS's own pictures aren't on this Mac")
        // A screenshot with words on it, read on this Mac.
        try render("ПАРОЛЬ WIFI 4821", to: directory.appendingPathComponent("Screenshot 2026-10-25.png"))

        let search = PhotoSearch(file: directory.appendingPathComponent("index/index.plist"), library: false)
        search.folders = { [directory] in [directory] }
        await search.refresh().value
        #expect(search.count == copied + 1)

        func names(_ words: String, keywords: [String] = []) async -> [String] {
            var query = PhotoQuery()
            query.words = words
            query.keywords = keywords
            return await search.find(query).matches.map(\.record.name)
        }
        let birds = await names("найди фото птицы")
        #expect(!birds.isEmpty)
        #expect(Set(birds.prefix(4)).isSubset(of: ["Eagle.heic", "Owl.heic", "Parrot.heic", "Penguin.heic"]))
        #expect(await names("zebra").first == "Zebra.heic")
        let flowers = await names("знайди фото квітів")
        #expect(!flowers.isEmpty)
        #expect(!flowers.contains("Zebra.heic"))
        #expect(await names("скрин где пароль 4821").first == "Screenshot 2026-10-25.png")
        #expect(await names("фото кота").isEmpty)

        // The index is kept, and erased on request.
        let reloaded = PhotoIndex.load(from: search.file)
        #expect(reloaded.records.count == copied + 1)
        #expect(reloaded.records.values.allSatisfy { $0.source == .file })
        search.clear()
        #expect(search.count == 0)
        #expect(!FileManager.default.fileExists(atPath: search.file.path))
    }

    /// A picture whose meaning is `likeness` alike to the request's (the first axis), with Vision's labels and words.
    private func record(_ name: String, likeness: Float, labels: [String: Float] = [:], text: String = "") -> PhotoRecord {
        var vector = [Float](repeating: 0, count: PhotoMeaning.length)
        vector[0] = likeness
        vector[1] = (1 - likeness * likeness).squareRoot()
        var record = PhotoRecord(source: .file, location: "/pictures/\(name)", name: name, taken: nil, changed: .now, labels: labels, text: text)
        record.meaning = PhotoMeaning.pack(vector)
        return record
    }

    private func found(_ records: [PhotoRecord], words: String, keywords: [String] = [], text: String = "") -> [(String, Bool)] {
        var index = PhotoIndex()
        for record in records { index.records[record.id] = record }
        var query = PhotoQuery()
        query.words = words
        query.scene = "what was asked for"
        query.keywords = keywords
        query.text = text
        var axis = [Float](repeating: 0, count: PhotoMeaning.length)
        axis[0] = 1
        query.vector = axis
        return index.search(query).map { ($0.record.name, $0.certain) }
    }

    @Test func meaningDecidesAndWhatOnlyComesCloseIsAMaybe() {
        let pictures = [record("sure.jpg", likeness: 0.30), record("close.jpg", likeness: 0.225), record("other.jpg", likeness: 0.12)]
        // Something sure: only that, never the ones that only come close.
        let sure = found(pictures, words: "кот")
        let allSure = sure.allSatisfy { $0.1 }
        #expect(sure.map(\.0) == ["sure.jpg"])
        #expect(allSure)
        // Nothing sure: the close one, said to be unsure; the unrelated one never.
        let unsure = found(Array(pictures.dropFirst()), words: "кот")
        let noneSure = unsure.allSatisfy { !$0.1 }
        #expect(unsure.map(\.0) == ["close.jpg"])
        #expect(noneSure)
        #expect(found([record("other.jpg", likeness: 0.12)], words: "кот").isEmpty)
    }

    @Test func visionsLabelsAndTheWordsReadOnlyAddToTheMeaning() {
        // Vision saw everything asked for: a little more, enough to be sure.
        let seen = record("cat-sofa.jpg", likeness: 0.225, labels: ["cat": 0.8, "sofa": 0.6])
        let half = record("cat.jpg", likeness: 0.225, labels: ["cat": 0.9])
        let both = found([seen, half], words: "кот на диване", keywords: ["cat", "sofa"])
        #expect(both.first.map { $0.0 } == "cat-sofa.jpg")
        #expect(both.first?.1 == true)
        let halfSure = both.contains { $0.0 == "cat.jpg" && $0.1 }
        #expect(!halfSure)
        // A word asked for that is written in the picture.
        let receipt = record("receipt.jpg", likeness: 0.2, labels: ["receipt": 0.7], text: "COFFEE LAB 12:45")
        #expect(found([receipt, record("menu.jpg", likeness: 0.2)], words: "чек", keywords: ["receipt"], text: "Coffee Lab").first.map { $0.0 } == "receipt.jpg")
    }

    @Test func withoutTheMeaningEveryThingAskedForMustBeSeen() {
        var index = PhotoIndex()
        for record in [PhotoRecord(source: .file, location: "/g.jpg", name: "g.jpg", taken: nil, changed: .now, labels: ["giraffe": 0.9]),
                       PhotoRecord(source: .file, location: "/s.jpg", name: "s.jpg", taken: nil, changed: .now, labels: ["snow": 0.9])] {
            index.records[record.id] = record
        }
        var query = PhotoQuery()
        query.words = "жираф в снегу"
        // A giraffe without snow, or snow without a giraffe, isn't what was asked for.
        #expect(index.search(query).isEmpty)
        query.words = "жираф"
        #expect(index.search(query).map(\.record.name) == ["g.jpg"])
    }

    @Test func aFirstIndexIsReadAndGainsMeaningLater() throws {
        let file = directory.appendingPathComponent("old/index.plist")
        var old = PhotoIndex()
        old.version = 1
        let picture = PhotoRecord(source: .file, location: "/a.jpg", name: "a.jpg", taken: nil, changed: .now, labels: ["dog": 0.9])
        old.records[picture.id] = picture
        try old.save(to: file)
        let read = PhotoIndex.load(from: file)
        #expect(read.version == 2)
        #expect(read.records[picture.id]?.labels == ["dog": 0.9])
        #expect(read.records[picture.id]?.meaning == nil)
    }

    @Test func theModelsWordsBecomeAScene() {
        let terms = PhotoTerms.parse(#"Sure! {"scene": "a cat on a sofa", "keywords": ["Cat", "sofa", "x"], "text": ""}"#)
        #expect(terms?.scene == "a cat on a sofa")
        #expect(terms?.keywords == ["cat", "sofa"])
        // Without the model's scene: its keywords, or the things the words name.
        var query = PhotoQuery()
        query.words = "найди фото кота на диване"
        #expect(PhotoSearch.scene(for: query).contains("cat"))
        query.keywords = ["dog", "photo"]
        #expect(PhotoSearch.scene(for: query) == "dog")
        query.scene = "a dog in the snow"
        #expect(PhotoSearch.scene(for: query) == "a dog in the snow")
    }

    /// The model itself, when its folder is given (MOULD_PHOTO_MODEL): open_clip's own tokens, and macOS's pictures found
    /// by what they show.
    @Test func theModelFindsPicturesByWhatTheyShow() async throws {
        guard let path = ProcessInfo.processInfo.environment["MOULD_PHOTO_MODEL"] else { return }
        let folder = URL(fileURLWithPath: path)
        let tokens = try CLIPTokens(vocabulary: folder.appendingPathComponent("vocab.json"), merges: folder.appendingPathComponent("merges.txt"))
        #expect(tokens.encode("a photo of a cat on a sofa").prefix(10) == [49406, 320, 1125, 539, 320, 2368, 525, 320, 15723, 49407])
        #expect(tokens.encode("a very long description " + String(repeating: "word ", count: 100)).count == CLIPTokens.length)
        #expect(tokens.encode("a very long description " + String(repeating: "word ", count: 100)).last == CLIPTokens.end)

        let samples = URL(fileURLWithPath: "/Library/User Pictures/Animals")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: samples.path)) ?? []
        for name in names where name.hasSuffix(".heic") {
            try FileManager.default.copyItem(at: samples.appendingPathComponent(name).resolvingSymlinksInPath(), to: directory.appendingPathComponent(name))
        }
        try #require(names.contains("Zebra.heic"), "macOS's own pictures aren't on this Mac")
        let search = PhotoSearch(file: directory.appendingPathComponent("meaning/index.plist"), library: false)
        search.folders = { [directory] in [directory] }
        search.modelFolder = folder
        await search.refresh().value
        #expect(search.model == .ready)
        func first(_ scene: String) async -> PhotoMatch? {
            var query = PhotoQuery()
            query.words = scene
            query.scene = scene
            return await search.find(query).matches.first
        }
        #expect(await first("a zebra")?.record.name == "Zebra.heic")
        #expect(await first("an owl")?.record.name == "Owl.heic")
        #expect(await first("a parrot")?.record.name == "Parrot.heic")
        // Nothing like a passport is among them: no sure answer.
        #expect(await first("a passport")?.certain != true)
    }

    /// The archive as it's published (MOULD_PHOTO_MODEL_ZIP): its checksum is the one the app expects, it unpacks into a
    /// model that opens, and a damaged one is turned away.
    @Test func thePublishedArchiveUnpacksIntoAWorkingModel() throws {
        guard let path = ProcessInfo.processInfo.environment["MOULD_PHOTO_MODEL_ZIP"] else { return }
        let archive = URL(fileURLWithPath: path)
        #expect(ModelDownload.sha256(of: archive) == PhotoModel.sha256)
        #expect((try FileManager.default.attributesOfItem(atPath: path)[.size] as? Int64) == PhotoModel.bytes)
        let folder = directory.appendingPathComponent("Models/PhotoMeaning-1", isDirectory: true)
        #expect(PhotoModel.unpack(archive, into: folder))
        #expect(PhotoModel.isInstalled(in: folder))
        let meaning = try PhotoMeaning(folder: folder)
        #expect(meaning.vector(of: "a cat")?.count == PhotoMeaning.length)
        let broken = directory.appendingPathComponent("broken.zip")
        try Data("not a zip".utf8).write(to: broken)
        #expect(!PhotoModel.unpack(broken, into: directory.appendingPathComponent("Models/Other", isDirectory: true)))
    }

    @Test func thePandaHasASwitchOfItsOwn() throws {
        let panda = try #require(FeatureGroup.all.first { $0.id == "panda" })
        #expect(panda.main.id == "islandPanda")
        #expect(panda.options.map(\.id) == ["pandaSounds"])
        let island = try #require(FeatureGroup.all.first { $0.id == "island" })
        #expect(!island.options.contains { $0.id == "islandPanda" || $0.id == "pandaSounds" })
        // Automations and the assistant still find it by the same id.
        #expect(AutomationEngine.featureKey("islandPanda") == \SuiteSettings.islandPanda)
    }

    private func render(_ text: String, to url: URL) throws {
        let size = NSSize(width: 1400, height: 420)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.white.setFill()
            rect.fill()
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 96, weight: .bold), .foregroundColor: NSColor.black]
            NSAttributedString(string: text, attributes: attributes).draw(at: NSPoint(x: 60, y: 150))
            return true
        }
        let data = try #require(image.tiffRepresentation.flatMap { NSBitmapImageRep(data: $0)?.representation(using: .png, properties: [:]) })
        try data.write(to: url)
    }
}
#endif
