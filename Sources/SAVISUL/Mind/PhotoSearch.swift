#if MOULD_ENGINE
import AppKit
import MouldEngine
import Observation
import Photos
import SwiftUI
import UniformTypeIdentifiers

/// Finding a picture by what is in it. The index covers the Photos library, when the person allows it, and the folders
/// the assistant may use; it catches up in the background and is searched on this Mac.
@MainActor
@Observable
final class PhotoSearch {
    static let shared = PhotoSearch()

    /// Whether the Photos library is searched too: off until the person turns it on and macOS agrees.
    private(set) var library: Bool
    private(set) var access: PHAuthorizationStatus
    /// Pictures in the index.
    private(set) var count = 0
    private(set) var updated: Date?
    /// Looked at and to look at, while the index catches up.
    private(set) var progress: (done: Int, total: Int)?
    /// The model that gives pictures and requests their meaning: downloaded once, then the search goes by it.
    private(set) var model: PhotoModel.State = PhotoModel.installed ? .ready : .missing

    @ObservationIgnored let file: URL
    /// The assistant's folders; a test hands in its own.
    @ObservationIgnored var folders: () -> [URL] = { MindHost.shared.folders }
    @ObservationIgnored private var index: PhotoIndex?
    /// The meaning, once loaded; a test hands in its own folder.
    @ObservationIgnored private var meaning: PhotoMeaning?
    @ObservationIgnored var modelFolder = PhotoModel.folder
    @ObservationIgnored private var download: ModelDownload?
    @ObservationIgnored private var job: Task<Void, Never>?
    @ObservationIgnored private var refreshed: Date?
    /// Erasing the index during a run makes what that run still finds go nowhere.
    @ObservationIgnored private var generation = 0

    init(file: URL = PhotoIndex.location, library: Bool = SettingsDefaults.store.bool(forKey: "photos.library")) {
        self.file = file
        self.library = library
        access = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    var running: Bool { job != nil }

    /// Reads the index from disk once, and the meaning when it's installed.
    func prepare() async {
        await loadMeaning()
        guard index == nil else { return }
        let file = self.file
        let loaded = await Task.detached(priority: .utility) { PhotoIndex.load(from: file) }.value
        guard index == nil else { return }
        index = loaded
        count = loaded.records.count
        updated = loaded.updated
    }

    private func loadMeaning() async {
        guard meaning == nil, PhotoModel.isInstalled(in: modelFolder) else { return }
        let folder = modelFolder
        do {
            meaning = try await Task.detached(priority: .utility) { try PhotoMeaning(folder: folder) }.value
            model = .ready
        } catch {
            // A broken install is removed, so the next download starts clean.
            try? FileManager.default.removeItem(at: folder)
            model = .failed(error.localizedDescription)
        }
    }

    /// Downloads the meaning (once, about 145 MB), checks it, installs it and looks at every picture with it.
    func installModel() {
        guard download == nil, meaning == nil else { return }
        model = .downloading(0)
        let archive = FileManager.default.temporaryDirectory.appendingPathComponent("savisul-photo-meaning-\(UUID().uuidString).zip")
        let folder = modelFolder
        let job = ModelDownload(url: PhotoModel.url, to: archive, bytes: PhotoModel.bytes, sha256: PhotoModel.sha256, progress: { fraction in
            Task { @MainActor in if case .downloading = PhotoSearch.shared.model { PhotoSearch.shared.model = .downloading(fraction) } }
        }, done: { problem in
            Task { @MainActor in await PhotoSearch.shared.installed(archive: archive, folder: folder, problem: problem) }
        })
        download = job
        job.start()
    }

    private func installed(archive: URL, folder: URL, problem: ModelDownload.Problem?) async {
        download = nil
        defer { try? FileManager.default.removeItem(at: archive) }
        if let problem {
            if case .checksum = problem { model = .failed(PhotoPhrases.modelDamaged.text) } else { model = .failed(PhotoPhrases.modelOffline.text) }
            return
        }
        let unpacked = await Task.detached(priority: .utility) { PhotoModel.unpack(archive, into: folder) }.value
        guard unpacked else {
            model = .failed(PhotoPhrases.modelDamaged.text)
            return
        }
        await loadMeaning()
        if meaning != nil { refresh() }
    }

    func cancelModel() {
        download?.cancel()
        download = nil
        model = .missing
    }

    /// Turning the library on asks macOS for access the first time; turning it off forgets what was seen in it.
    func setLibrary(_ on: Bool) {
        library = on
        SettingsDefaults.store.set(on, forKey: "photos.library")
        guard on else {
            job?.cancel()
            Task {
                await prepare()
                if var kept = index {
                    kept.records = kept.records.filter { $0.value.source != .library }
                    index = kept
                }
                count = index?.records.count ?? 0
                await save()
            }
            return
        }
        access = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if access == .notDetermined {
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                Task { @MainActor in
                    PhotoSearch.shared.access = status
                    if status == .authorized { PhotoSearch.shared.refresh() }
                }
            }
        } else if access == .authorized {
            refresh()
        }
    }

    /// Asked for a photo before Photos was ever allowed or refused: asks macOS now, and searches the library when allowed.
    func askForLibraryIfUndecided() async {
        guard PHPhotoLibrary.authorizationStatus(for: .readWrite) == .notDetermined else { return }
        let status = await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { continuation.resume(returning: $0) }
        }
        access = status
        if status == .authorized { setLibrary(true) }
    }

    /// Brings the index up to date: new and changed pictures are looked at, newest first; ones that are gone are
    /// forgotten; with the meaning installed, pictures looked at before it gain theirs. One run at a time.
    @discardableResult
    func refresh() -> Task<Void, Never> {
        if let job { return job }
        let folders = folders()
        let library = self.library && access == .authorized
        let generation = self.generation
        let job = Task { [weak self] in
            await self?.prepare()
            let known = await MainActor.run { self?.index?.records ?? [:] }
            let items = await Task.detached(priority: .utility) {
                PhotoIndexer.files(in: folders) + (library ? PhotoIndexer.library() : [])
            }.value
            guard let self, self.generation == generation else { return }
            let meaning = self.meaning
            let present = Set(items.map(\.id))
            let work = items.filter { item in known[item.id].map { $0.changed < item.changed } ?? true }
            let changed = Set(work.map(\.id))
            let unmeant = meaning == nil ? [] : known.values.filter { present.contains($0.id) && !changed.contains($0.id) && $0.meaning == nil }
            if var kept = self.index {
                kept.records = kept.records.filter { present.contains($0.key) }
                self.index = kept
            }
            self.count = self.index?.records.count ?? 0
            let total = work.count + unmeant.count
            self.progress = total == 0 ? nil : (0, total)
            var done = 0
            for start in stride(from: 0, to: work.count, by: 24) {
                guard !Task.isCancelled, self.generation == generation else { break }
                let batch = Array(work[start..<min(start + 24, work.count)])
                let records = await Task.detached(priority: .utility) { await Self.look(at: batch, meaning: meaning) }.value
                guard self.generation == generation else { break }
                for record in records { self.index?.records[record.id] = record }
                done += batch.count
                self.count = self.index?.records.count ?? 0
                self.progress = (done, total)
                if done % 480 == 0 { await self.save() }
            }
            if let meaning {
                for start in stride(from: 0, to: unmeant.count, by: 48) {
                    guard !Task.isCancelled, self.generation == generation else { break }
                    let batch = Array(unmeant[start..<min(start + 48, unmeant.count)])
                    let records = await Task.detached(priority: .utility) { batch.map { PhotoIndexer.mean($0, meaning: meaning) } }.value
                    guard self.generation == generation else { break }
                    for record in records where self.index?.records[record.id] != nil { self.index?.records[record.id] = record }
                    done += batch.count
                    self.progress = (done, total)
                    if done % 480 < 48 { await self.save() }
                }
            }
            guard self.generation == generation else { return }
            if !Task.isCancelled {
                self.index?.updated = .now
                self.updated = .now
                self.refreshed = .now
            }
            self.progress = nil
            self.job = nil
            await self.save()
        }
        self.job = job
        return job
    }

    /// Three pictures at a time: Vision is quick, decoding them is the slow part.
    nonisolated private static func look(at items: [PhotoIndexer.Item], meaning: PhotoMeaning?) async -> [PhotoRecord] {
        await withTaskGroup(of: PhotoRecord.self) { group in
            var pending = items.makeIterator()
            for _ in 0..<3 {
                guard let item = pending.next() else { break }
                group.addTask { PhotoIndexer.look(at: item, meaning: meaning) }
            }
            var records: [PhotoRecord] = []
            while let record = await group.next() {
                records.append(record)
                if let item = pending.next() { group.addTask { PhotoIndexer.look(at: item, meaning: meaning) } }
            }
            return records
        }
    }

    func clear() {
        generation += 1
        job?.cancel()
        job = nil
        progress = nil
        index = PhotoIndex()
        count = 0
        updated = nil
        refreshed = nil
        try? FileManager.default.removeItem(at: file)
    }

    private func save() async {
        guard let index else { return }
        let file = self.file
        await Task.detached(priority: .utility) { try? index.save(to: file) }.value
    }

    /// Searches the index, letting it catch up for a while first; what it hasn't reached yet is found next time.
    func find(_ query: PhotoQuery, wait: Duration = .seconds(20)) async -> (matches: [PhotoMatch], indexed: Int, pending: Int) {
        await prepare()
        let stale = refreshed.map { Date().timeIntervalSince($0) > 600 } ?? true
        if stale || job != nil {
            refresh()
            let deadline = ContinuousClock.now + wait
            while job != nil && ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(250)) }
        }
        let snapshot = index ?? PhotoIndex()
        var query = query
        if let meaning, case let scene = Self.scene(for: query), !scene.isEmpty {
            query.vector = await Task.detached(priority: .userInitiated) { meaning.vector(of: "a photo of \(scene)") }.value
        }
        let asked = query
        let matches = await Task.detached(priority: .userInitiated) { snapshot.search(asked) }.value
        return (matches, snapshot.records.count, progress.map { $0.total - $0.done } ?? 0)
    }

    /// What the picture should show, in English, for the meaning: the model's own words for it, or else its keywords, or
    /// else the things the person's words name.
    nonisolated static func scene(for query: PhotoQuery) -> String {
        let scene = query.scene.trimmingCharacters(in: .whitespacesAndNewlines)
        if !scene.isEmpty { return scene }
        let keywords = query.keywords.filter { !PhotoWords.isStop($0.lowercased()) }
        if !keywords.isEmpty { return keywords.joined(separator: ", ") }
        return PhotoWords.plan(query, now: .now).concepts.compactMap { $0.first?.replacingOccurrences(of: "_", with: " ") }.joined(separator: ", ")
    }

    nonisolated static func day(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: text.trimmingCharacters(in: .whitespaces))
    }

    /// "Find the photo of…" and nothing else: such a request goes straight to the search, which a small model on this
    /// Mac handles far more reliably than a conversation with tools. Anything asking more ("…and put it on the Shelf")
    /// goes to the model.
    nonisolated static func isPhotoRequest(_ text: String) -> Bool {
        let words = PhotoWords.tokens(text)
        guard !words.isEmpty, words.count <= 24 else { return false }
        func has(_ stems: [String], whole: Set<String> = []) -> Bool {
            words.contains { word in whole.contains(word) || stems.contains { word.hasPrefix($0) } }
        }
        let picture = has(["фото", "фотк", "фотограф", "снимок", "снимк", "картинк", "изображен", "скрин", "селфи", "світлин", "знімк", "зображен", "селфі", "скріншот"],
                          whole: ["photo", "photos", "picture", "pictures", "pic", "pics", "image", "images", "screenshot", "screenshots", "selfie", "selfies"])
        let looking = has(["найд", "найт", "поищ", "покаж", "знайд", "знайт", "пошук", "шука", "search"],
                          whole: ["где", "де", "ищу", "ищи", "find", "show", "where", "look"])
        let more = has(["полож", "перемест", "удал", "переимен", "отправ", "скопир", "сожм", "конверт", "сохран", "покласт", "поклад", "переміст", "видал",
                        "перейменуй", "надішл", "скопію", "стисн", "збереж", "подел", "поділ"],
                       whole: ["put", "move", "delete", "rename", "send", "copy", "convert", "save", "share"])
        return picture && looking && !more
    }
}

// MARK: The tool

extension MindTools {
    static let findPhotos = FunctionTool(
        ToolSpec(name: "photos.find", title: "Find photos",
                 summary: "Finds photos and pictures by what is in them (animals, people, food, places, documents, receipts, screenshots), by words written on them and by when they were taken: the Photos library, when the person allowed it, and pictures in the folders the assistant may use. Everything is recognized on this Mac. The pictures found are shown to the person as thumbnails; just say briefly what you found.",
                 input: .object([
                    "query": .string("The person's own words for the picture, as they said them.", maxLength: 300),
                    "scene": .string("What the picture shows, in plain English, e.g. \"a cat sleeping on a sofa\".", maxLength: 200),
                    "keywords": .array(of: .string(maxLength: 40), description: "What should be visible, as short English nouns, e.g. [\"cat\", \"sofa\"].", maxItems: 8),
                    "text": .string("Words written in the picture, if the person said any.", maxLength: 200),
                    "after": .string("Taken on or after this day, YYYY-MM-DD.", maxLength: 10),
                    "before": .string("Taken before this day, YYYY-MM-DD.", maxLength: 10),
                    "limit": .integer(minimum: 1, maximum: 60)
                 ], required: ["query"]),
                 effects: [.read], risk: .low, timeout: .seconds(90), idempotent: true)
    ) { arguments, context in
        var query = PhotoQuery()
        query.words = arguments["query"]?.string ?? ""
        query.scene = arguments["scene"]?.string ?? ""
        query.keywords = arguments["keywords"]?.array?.compactMap(\.string) ?? []
        query.text = arguments["text"]?.string ?? ""
        query.after = arguments["after"]?.string.flatMap(PhotoSearch.day)
        query.before = arguments["before"]?.string.flatMap(PhotoSearch.day)
        query.limit = arguments["limit"]?.int ?? 24
        let result = await PhotoSearch.shared.find(query)
        let hits = result.matches.map { PhotoHit($0.record) }
        await MainActor.run { MindHost.shared.conversation.found(hits) }
        let days = ISO8601DateFormatter()
        days.formatOptions = [.withFullDate]
        let items: [JSONValue] = result.matches.map { match in
            var item: [String: JSONValue] = ["name": .string(match.record.name), "taken": .string(days.string(from: match.record.date)),
                                             "shows": .array(match.matched.prefix(4).map(JSONValue.string)), "sure": .bool(match.certain)]
            if match.record.source == .file { item["path"] = .string(match.record.location) }
            if !match.record.text.isEmpty { item["text"] = .string(String(match.record.text.prefix(80))) }
            return .object(item)
        }
        let sure = result.matches.contains(where: \.certain)
        return ToolOutput(["found": .number(Double(hits.count)), "sure": .bool(sure), "indexed": .number(Double(result.indexed)),
                           "stillToIndex": .number(Double(result.pending)), "items": .array(items), "shownToPerson": .bool(true)],
                          summary: hits.isEmpty ? "No pictures found" : sure ? "Found \(hits.count) pictures" : "Nothing sure; \(hits.count) that come close",
                          untrusted: true)
    }
}

/// The model on this Mac turns the person's description into English names for what should be visible and the words
/// written on it. The description never leaves the Mac; without a local model, the search goes on with its own words.
enum PhotoTerms {
    struct Terms: Sendable {
        var scene: String
        var keywords: [String]
        var text: String
    }

    static let instructions = """
    You turn a request to find photos into search terms. Reply with one line of JSON and nothing else: \
    {"scene": "what the photo shows, in plain English, a few words", "keywords": [short English nouns for what is visible], \
    "text": "only words the person says are written in the photo, kept in their own language, or empty"}. \
    Leave out when it was taken and words like photo or picture. \
    Example: "найди фото кота на диване" → {"scene": "a cat on a sofa", "keywords": ["cat", "sofa"], "text": ""}. \
    Example: "знайди фото з моря минулого літа" → {"scene": "the sea", "keywords": ["sea", "beach"], "text": ""}. \
    Example: "чек из кафе, где написано Coffee Lab" → {"scene": "a receipt from a cafe", "keywords": ["receipt"], "text": "Coffee Lab"}. \
    Example: "скрин, где написано пароль от wifi" → {"scene": "a screenshot with a Wi-Fi password", "keywords": ["screenshot"], "text": "пароль wifi"}. \
    Example: "скриншот с ошибкой" → {"scene": "a screenshot of an error message", "keywords": ["screenshot", "error"], "text": ""}.
    """

    /// With the person's own AI (`model`) the words go to it, as any request they type does; otherwise only a model on
    /// this Mac reads them.
    static func read(_ prompt: String, engine: MouldEngine, model: String? = nil) async -> Terms? {
        let request = model.map { CompletionRequest(prompt, instructions: instructions, maxTokens: 128, sensitivity: .open, model: $0) }
            ?? CompletionRequest(prompt, instructions: instructions, maxTokens: 128, sensitivity: .personal, localOnly: true)
        var reply = ""
        do {
            for try await event in await engine.complete(request) {
                if case .text(let piece) = event { reply += piece }
            }
        } catch {
            return nil
        }
        return parse(reply)
    }

    /// The model's one line of JSON, read leniently: the first object in the reply.
    static func parse(_ reply: String) -> Terms? {
        guard let start = reply.firstIndex(of: "{"), let end = reply.lastIndex(of: "}"), start < end,
              let object = try? JSONSerialization.jsonObject(with: Data(reply[start...end].utf8)) as? [String: Any] else { return nil }
        let keywords = (object["keywords"] as? [Any] ?? []).compactMap { $0 as? String }
            .map { $0.lowercased().trimmingCharacters(in: .whitespaces) }.filter { (2...40).contains($0.count) }
        let scene = (object["scene"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return Terms(scene: String(scene.prefix(200)), keywords: Array(keywords.prefix(8)), text: String((object["text"] as? String ?? "").prefix(200)))
    }
}

// MARK: What was found

/// One picture found, as the assistant's panel shows it.
struct PhotoHit: Identifiable, Hashable, Sendable {
    let source: PhotoRecord.Source
    let location: String
    let name: String
    let taken: Date

    init(_ record: PhotoRecord) {
        source = record.source
        location = record.location
        name = record.name
        taken = record.date
    }

    var id: String { "\(source.rawValue):\(location)" }
}

/// Opening, dragging and keeping a picture that was found. A library picture is copied out of Photos (from iCloud if
/// it has to be) into SAVISUL's caches the first time it's needed as a file.
@MainActor
enum PhotoActions {
    static func thumbnail(_ photo: PhotoHit, size: CGFloat) async -> NSImage? {
        switch photo.source {
        case .file:
            let path = photo.location
            let image = await Task.detached(priority: .userInitiated) { () -> CGImage? in
                guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else { return nil }
                let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                                                kCGImageSourceThumbnailMaxPixelSize: Int(size * 2)]
                return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
            }.value
            return image.map { NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height)) }
        case .library:
            guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [photo.location], options: nil).firstObject else { return nil }
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = true
            return await withCheckedContinuation { continuation in
                PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: size * 2, height: size * 2), contentMode: .aspectFill,
                                                      options: options) { image, _ in continuation.resume(returning: image) }
            }
        }
    }

    /// The picture as a file on this Mac.
    static func file(_ photo: PhotoHit) async -> URL? {
        guard photo.source == .library else { return URL(fileURLWithPath: photo.location) }
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [photo.location], options: nil).firstObject else { return nil }
        let resources = PHAssetResource.assetResources(for: asset)
        guard let resource = resources.first(where: { $0.type == .photo || $0.type == .fullSizePhoto }) ?? resources.first else { return nil }
        let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SAVISUL/Photos/" + photo.location.replacingOccurrences(of: "/", with: "-"))
        let target = folder.appendingPathComponent(resource.originalFilename)
        if FileManager.default.fileExists(atPath: target.path) { return target }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true
        return await withCheckedContinuation { continuation in
            PHAssetResourceManager.default().writeData(for: resource, toFile: target, options: options) { error in
                continuation.resume(returning: error == nil ? target : nil)
            }
        }
    }

    static func open(_ photo: PhotoHit) {
        Task { if let url = await file(photo) { NSWorkspace.shared.open(url) } }
    }

    static func reveal(_ photo: PhotoHit) {
        Task { if let url = await file(photo) { NSWorkspace.shared.activateFileViewerSelecting([url]) } }
    }

    static func shelve(_ photos: [PhotoHit]) {
        Task {
            var urls: [URL] = []
            for photo in photos { if let url = await file(photo) { urls.append(url) } }
            if !urls.isEmpty { Suite.shared.shelf.add(urls: urls) }
        }
    }

    static func copy(_ photo: PhotoHit) {
        Task {
            guard let url = await file(photo) else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([url as NSURL])
        }
    }

    static func provider(_ photo: PhotoHit) -> NSItemProvider {
        if photo.source == .file, let provider = NSItemProvider(contentsOf: URL(fileURLWithPath: photo.location)) { return provider }
        let provider = NSItemProvider()
        provider.suggestedName = photo.name
        provider.registerFileRepresentation(forTypeIdentifier: UTType.image.identifier, fileOptions: [], visibility: .all) { completion in
            Task { @MainActor in
                let url = await file(photo)
                completion(url, false, url == nil ? CocoaError(.fileReadUnknown) : nil)
            }
            return nil
        }
        return provider
    }
}

/// The pictures found, in the assistant's panel: click to open, drag anywhere, more in the menu.
struct PhotoGrid: View {
    let photos: [PhotoHit]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(photos) { PhotoTile(photo: $0) }
            }
            if photos.count > 1 {
                PillButton(title: PhotoPhrases.shelveAll.text, symbol: "tray.and.arrow.down") { PhotoActions.shelve(photos) }
            }
        }
    }
}

private struct PhotoTile: View {
    let photo: PhotoHit
    @State private var image: NSImage?
    @State private var hover = false

    var body: some View {
        Color.white.opacity(0.06)
            .frame(height: 112)
            .overlay {
                if let image {
                    Image(nsImage: image).resizable().scaledToFill()
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .overlay(alignment: .bottomLeading) {
                if hover {
                    Text(photo.taken.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(Suite.shared.language.locale)))
                        .font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(Capsule().fill(Color.black.opacity(0.55)))
                        .padding(6)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .onHover { hover = $0 }
            .onTapGesture { PhotoActions.open(photo) }
            .onDrag { PhotoActions.provider(photo) }
            .contextMenu {
                Button(MindPhrases.open.text) { PhotoActions.open(photo) }
                Button(PhotoPhrases.reveal.text) { PhotoActions.reveal(photo) }
                Button(PhotoPhrases.shelve.text) { PhotoActions.shelve([photo]) }
                Button(PhotoPhrases.copy.text) { PhotoActions.copy(photo) }
            }
            .help(photo.name)
            .task(id: photo.id) { image = await PhotoActions.thumbnail(photo, size: 140) }
    }
}

// MARK: Settings

/// Settings → Assistant → Photo search: the Photos library, what the index holds, and its buttons.
struct PhotoSettings: View {
    let search: PhotoSearch

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(PhotoPhrases.title.text).font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.tertiary)
            MeaningRow(search: search)
            ToggleRow(symbol: "photo.on.rectangle.angled", tint: Palette.accent, title: PhotoPhrases.library.text,
                      detail: (search.library && search.access == .authorized ? PhotoPhrases.libraryOn : PhotoPhrases.libraryOff).text,
                      isOn: search.library && search.access == .authorized) { search.setLibrary(!(search.library && search.access == .authorized)) }
            if search.library && (search.access == .denied || search.access == .restricted) {
                HStack(alignment: .top, spacing: 8) {
                    Text(PhotoPhrases.denied.text).font(.system(size: 11)).foregroundStyle(Palette.warning).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    PillButton(title: PhotoPhrases.openSettings.text) {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Photos") { NSWorkspace.shared.open(url) }
                    }
                }
            }
            if let progress = search.progress {
                HStack(spacing: 8) {
                    ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1))).tint(Palette.accent)
                    Text(PhotoPhrases.looking(progress.done, progress.total)).font(.system(size: 11.5, weight: .medium)).foregroundStyle(Palette.secondary)
                        .monospacedDigit().lineLimit(1)
                }
            } else {
                Text(status).font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    PillButton(title: PhotoPhrases.update.text, symbol: "arrow.clockwise") { search.refresh() }
                    PillButton(title: PhotoPhrases.erase.text, tint: Palette.danger) { search.clear() }
                        .disabled(search.count == 0)
                    Spacer(minLength: 0)
                }
            }
            Footnote(PhotoPhrases.footnote.text)
        }
        // Panel renders (--dump-panels) never read the person's index.
        .task { if Suite.shared.app != nil { await search.prepare() } }
    }

    private var status: String {
        guard search.count > 0 else { return PhotoPhrases.empty.text }
        let time = search.updated.map { $0.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(Suite.shared.language.locale)) } ?? "—"
        return PhotoPhrases.indexed(Say.number(search.count), time)
    }
}

/// The model for search by meaning: download it, watch it come, or see that it's on.
private struct MeaningRow: View {
    let search: PhotoSearch

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            RowIcon(symbol: "sparkle.magnifyingglass", tint: Palette.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(PhotoPhrases.meaning.text).font(.system(size: 13.5, weight: .medium)).foregroundStyle(Palette.ink)
                Text(detail).font(.system(size: 11.5)).foregroundStyle(failed ? Palette.warning : Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 10)
            switch search.model {
            case .missing, .failed:
                PillButton(title: PhotoPhrases.download.text, symbol: "arrow.down.circle") { search.installModel() }
            case let .downloading(fraction):
                ProgressView(value: fraction).tint(Palette.accent).frame(width: 64)
                PillButton(title: MindPhrases.stop.text) { search.cancelModel() }
            case .ready:
                Image(systemName: "checkmark.circle.fill").font(.system(size: 15)).foregroundStyle(Palette.positive)
            }
        }
        .padding(.vertical, 6)
    }

    private var failed: Bool {
        if case .failed = search.model { return true }
        return false
    }

    private var detail: String {
        switch search.model {
        case .missing: PhotoPhrases.meaningMissing.text
        case let .downloading(fraction): PhotoPhrases.downloading(Int((fraction * 100).rounded()))
        case .ready: PhotoPhrases.meaningReady.text
        case let .failed(problem): problem
        }
    }
}

// MARK: Words

enum PhotoPhrases {
    static let title = Phrase("Photo search", ru: "Поиск по фото", uk: "Пошук за фото", fr: "Recherche de photos")
    static let library = Phrase("Photos library", ru: "Медиатека «Фото»", uk: "Медіатека «Фото»", fr: "Photothèque")
    static let libraryOn = Phrase("Searched along with the pictures in the folders above", ru: "Ищется вместе с картинками из папок выше",
                                  uk: "Шукається разом зі зображеннями з тек вище", fr: "Fouillée avec les images des dossiers ci-dessus")
    static let libraryOff = Phrase("Off: only the pictures in the folders above are searched", ru: "Выключено: ищутся только картинки из папок выше",
                                   uk: "Вимкнено: шукаються лише зображення з тек вище", fr: "Désactivée : seules les images des dossiers ci-dessus sont fouillées")
    static let denied = Phrase("macOS doesn’t let SAVISUL see Photos. Allow it in System Settings → Privacy & Security → Photos.",
                               ru: "macOS не даёт SAVISUL доступ к «Фото». Разрешите его в Системных настройках → Конфиденциальность и безопасность → Фото.",
                               uk: "macOS не дає SAVISUL доступу до «Фото». Дозвольте його в Системних параметрах → Приватність і безпека → Фото.",
                               fr: "macOS ne laisse pas SAVISUL voir Photos. Autorisez-le dans Réglages Système → Confidentialité et sécurité → Photos.")
    static let openSettings = Phrase("Open Settings", ru: "Открыть настройки", uk: "Відкрити параметри", fr: "Ouvrir les Réglages")
    static let empty = Phrase("Nothing indexed yet: it fills in with the first search, or with Update.",
                              ru: "Индекс пока пуст: он соберётся при первом поиске или по кнопке «Обновить».",
                              uk: "Індекс поки порожній: він збереться під час першого пошуку або за кнопкою «Оновити».",
                              fr: "Rien d’indexé pour l’instant : l’index se remplit à la première recherche, ou avec Mettre à jour.")
    static let update = Phrase("Update", ru: "Обновить", uk: "Оновити", fr: "Mettre à jour")
    static let erase = Phrase("Erase", ru: "Стереть", uk: "Стерти", fr: "Effacer")
    static let footnote = Phrase("Pictures are recognized on this Mac with Apple’s Vision and, once downloaded, CLIP (LAION, MIT licence): what is in them, what they mean, the words on them and when they were taken. Nothing is sent anywhere. Ask the assistant: “Find the photo of a cat on the sofa”.",
                                 ru: "Картинки разбираются прямо на этом Mac — Apple Vision и, когда скачана, моделью CLIP (LAION, лицензия MIT): что на них, о чём они, какие на них слова и когда они сняты. Никуда ничего не отправляется. Спросите ассистента: «Найди фото кота на диване».",
                                 uk: "Зображення розбираються просто на цьому Mac — Apple Vision і, коли завантажена, моделлю CLIP (LAION, ліцензія MIT): що на них, про що вони, які на них слова й коли їх знято. Нікуди нічого не надсилається. Запитайте асистента: «Знайди фото кота на дивані».",
                                 fr: "Les images sont analysées sur ce Mac avec Vision d’Apple et, une fois téléchargé, CLIP (LAION, licence MIT) : ce qu’elles montrent, ce qu’elles signifient, les mots qu’elles contiennent et leur date. Rien n’est envoyé. Demandez à l’assistant : « Trouve la photo du chat sur le canapé ».")
    static let meaning = Phrase("Search by meaning", ru: "Поиск по смыслу", uk: "Пошук за змістом", fr: "Recherche par le sens")
    static let meaningMissing = Phrase("Understands what a picture shows, not just labels: 138 MB, once, works on this Mac",
                                       ru: "Понимает, что на снимке, а не только метки: 138 МБ, один раз, работает на этом Mac",
                                       uk: "Розуміє, що на знімку, а не лише мітки: 138 МБ, один раз, працює на цьому Mac",
                                       fr: "Comprend ce que montre une image, pas seulement des étiquettes : 138 Mo, une fois, sur ce Mac")
    static let meaningReady = Phrase("On: pictures are found by what they show", ru: "Включено: снимки ищутся по смыслу",
                                     uk: "Увімкнено: знімки шукаються за змістом", fr: "Activée : les images sont trouvées par ce qu’elles montrent")
    static let download = Phrase("Download", ru: "Скачать", uk: "Завантажити", fr: "Télécharger")
    static let modelDamaged = Phrase("The download came damaged. Try again.", ru: "Загрузка пришла повреждённой. Попробуйте ещё раз.",
                                     uk: "Завантаження прийшло пошкодженим. Спробуйте ще раз.", fr: "Le téléchargement est arrivé endommagé. Réessayez.")
    static let modelOffline = Phrase("Couldn’t download it. Check the connection and try again.", ru: "Не получилось скачать. Проверьте интернет и попробуйте снова.",
                                     uk: "Не вдалося завантажити. Перевірте інтернет і спробуйте знову.", fr: "Téléchargement impossible. Vérifiez la connexion et réessayez.")
    static let modelOffer = Phrase("To find pictures by what they show, not only by labels, download search by meaning in Settings → Assistant → Photo search (138 MB).",
                                   ru: "Чтобы искать снимки по смыслу, а не только по меткам, скачайте «Поиск по смыслу»: Настройки → Ассистент → Поиск по фото (138 МБ).",
                                   uk: "Щоб шукати знімки за змістом, а не лише за мітками, завантажте «Пошук за змістом»: Налаштування → Асистент → Пошук за фото (138 МБ).",
                                   fr: "Pour trouver les images par ce qu’elles montrent, pas seulement par étiquettes, téléchargez la recherche par le sens : Réglages → Assistant → Recherche de photos (138 Mo).")
    static let quick = Phrase("Find photos", ru: "Найти фото", uk: "Знайти фото", fr: "Trouver des photos")
    static let prompt = Phrase("Find the photo of ", ru: "Найди фото, где ", uk: "Знайди фото, де ", fr: "Trouve la photo de ")
    static let understanding = Phrase("Understanding the description", ru: "Понимаю описание", uk: "Розумію опис", fr: "Compréhension de la description")
    static let nothing = Phrase("Nothing found. Try other words, or check that the pictures are in Photos or in the assistant’s folders.",
                                ru: "Ничего не нашлось. Попробуйте другие слова или проверьте, что картинки есть в «Фото» или в папках ассистента.",
                                uk: "Нічого не знайшлося. Спробуйте інші слова або перевірте, що зображення є у «Фото» чи в теках асистента.",
                                fr: "Rien trouvé. Essayez d’autres mots, ou vérifiez que les images sont dans Photos ou dans les dossiers de l’assistant.")
    static let nothingWithoutLibrary = Phrase("Nothing found in Downloads and on the Desktop. Turn on Photos library in Settings → Assistant → Photo search, and I’ll look there too.",
                                              ru: "В «Загрузках» и на «Рабочем столе» ничего не нашлось. Включите «Медиатеку «Фото»» в Настройки → Ассистент → Поиск по фото — тогда поищу и там.",
                                              uk: "У «Завантаженнях» і на «Робочому столі» нічого не знайшлося. Увімкніть «Медіатеку «Фото»» в Налаштування → Асистент → Пошук за фото — тоді пошукаю й там.",
                                              fr: "Rien dans Téléchargements ni sur le Bureau. Activez la Photothèque dans Réglages → Assistant → Recherche de photos, et je chercherai aussi là.")
    static let describe = Phrase("Say what is in the photo: “a cat on the sofa”, “a receipt from a café”, “the sea last summer”.",
                                 ru: "Скажите, что на фото: «кот на диване», «чек из кафе», «море прошлым летом».",
                                 uk: "Скажіть, що на фото: «кіт на дивані», «чек із кафе», «море минулого літа».",
                                 fr: "Dites ce que montre la photo : « un chat sur le canapé », « un ticket de café », « la mer l’été dernier ».")
    static let reveal = Phrase("Show in Finder", ru: "Показать в Finder", uk: "Показати у Finder", fr: "Afficher dans le Finder")
    static let shelve = Phrase("Put on the Shelf", ru: "Положить на полку", uk: "Покласти на полицю", fr: "Mettre sur l’étagère")
    static let shelveAll = Phrase("All on the Shelf", ru: "Все на полку", uk: "Усі на полицю", fr: "Tout sur l’étagère")
    static let copy = Phrase("Copy", ru: "Скопировать", uk: "Скопіювати", fr: "Copier")

    @MainActor static func indexed(_ count: String, _ time: String) -> String {
        Phrase("Pictures in the index: %@ · updated %@", ru: "Картинок в индексе: %@ · обновлено %@", uk: "Зображень в індексі: %@ · оновлено %@",
               fr: "Images indexées : %@ · mise à jour %@")(count, time)
    }

    @MainActor static func looking(_ done: Int, _ total: Int) -> String {
        Phrase("Looking through pictures: %@ of %@", ru: "Разбираю картинки: %@ из %@", uk: "Розбираю зображення: %@ з %@", fr: "Analyse des images : %@ sur %@")(
            Say.number(done), Say.number(total))
    }

    @MainActor static func found(_ count: Int) -> String {
        Phrase("Found pictures: %d. Click one to open it, or drag it anywhere.", ru: "Найдено картинок: %d. Нажмите, чтобы открыть, или перетащите куда нужно.",
               uk: "Знайдено зображень: %d. Натисніть, щоб відкрити, або перетягніть куди треба.",
               fr: "Images trouvées : %d. Cliquez pour ouvrir, ou faites glisser où vous voulez.")(count)
    }

    @MainActor static func maybe(_ count: Int) -> String {
        Phrase("Nothing that surely matches. These come closest (%d):", ru: "Точно такого не нашлось. Ближе всего — эти (%d):",
               uk: "Точно такого не знайшлося. Найближчі — ці (%d):", fr: "Rien qui corresponde sûrement. Les plus proches (%d) :")(count)
    }

    @MainActor static func downloading(_ percent: Int) -> String {
        Phrase("Downloading: %d%%", ru: "Скачиваю: %d%%", uk: "Завантажую: %d%%", fr: "Téléchargement : %d %%")(percent)
    }

    @MainActor static func stillLooking(_ count: Int) -> String {
        Phrase("Still looking through pictures (%d to go): ask again in a minute.", ru: "Ещё разбираю картинки (осталось %d) — спросите снова через минуту.",
               uk: "Ще розбираю зображення (лишилося %d) — запитайте знову за хвилину.", fr: "Analyse en cours (encore %d) : redemandez dans une minute.")(count)
    }
}
#endif
