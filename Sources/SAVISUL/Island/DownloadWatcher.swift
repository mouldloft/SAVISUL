import AppKit
import Observation

/// Watches ~/Downloads for browser partial files and for files that just landed.
/// The SAVISUL browser extension adds exact progress for Chromium downloads.
@MainActor
@Observable
final class DownloadWatcher {
    struct Active: Identifiable, Equatable {
        var id: String
        var name: String
        var bytes: Int64
        var total: Int64?
        var speed: Double
        var source: String
        var started: Date

        var progress: Double? {
            guard let total, total > 0 else { return nil }
            return min(Double(bytes) / Double(total), 1)
        }

        var remaining: Double? {
            guard let total, speed > 1 else { return nil }
            return Double(max(total - bytes, 0)) / speed
        }
    }

    struct Finished: Identifiable, Equatable {
        var id: String { url.path }
        var url: URL
        var name: String
        var size: Int64
        var date: Date
    }

    private(set) var active: [Active] = []
    private(set) var finished: [Finished] = []
    @ObservationIgnored var onFinished: ((Finished) -> Void)?
    @ObservationIgnored var onStarted: ((Active) -> Void)?

    @ObservationIgnored private var source: DispatchSourceFileSystemObject?
    @ObservationIgnored private var poll: Timer?
    @ObservationIgnored private var known: Set<String> = []
    @ObservationIgnored private var samples: [String: (bytes: Int64, date: Date, speed: Double, started: Date)] = [:]
    @ObservationIgnored private var browser: [String: Active] = [:]
    @ObservationIgnored private var recent: [String: Date] = [:]
    @ObservationIgnored private var pending = false

    static let folder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
    private static let partial: [String: String] = [
        "crdownload": "Chrome", "download": "Safari", "part": "Firefox", "partial": "Edge", "opdownload": "Opera"
    ]

    func start() {
        guard source == nil else { return }
        let descriptor = Darwin.open(Self.folder.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.schedule() } }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        self.source = source
        scan(initial: true)
    }

    func stop() {
        source?.cancel()
        source = nil
        poll?.invalidate()
        poll = nil
    }

    func reveal(_ item: Finished) { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
    func open(_ item: Finished) { NSWorkspace.shared.open(item.url) }
    func openFolder() { NSWorkspace.shared.open(Self.folder) }

    func forget(_ item: Finished) { finished.removeAll { $0.id == item.id } }

    /// Progress reported by the browser extension: { id, name, received, total, state }.
    func browserUpdate(_ payload: [String: Any]) {
        guard let id = payload["id"].map({ "browser-\($0)" }) else { return }
        let state = payload["state"] as? String ?? "in_progress"
        let name = (payload["name"] as? String).map { ($0 as NSString).lastPathComponent } ?? ""
        if state == "in_progress" {
            let received = Int64(payload["received"] as? Double ?? 0)
            let total = (payload["total"] as? Double).flatMap { $0 > 0 ? Int64($0) : nil }
            var item = browser[id] ?? Active(id: id, name: name, bytes: 0, total: total, speed: 0,
                                             source: payload["browser"] as? String ?? "Chrome", started: Date())
            let isNew = browser[id] == nil
            let elapsed = max(Date().timeIntervalSince(samples[id]?.date ?? item.started), 0.2)
            let instant = Double(received - item.bytes) / elapsed
            item.speed = item.speed == 0 ? instant : item.speed * 0.7 + instant * 0.3
            item.bytes = received
            item.total = total
            if !name.isEmpty { item.name = name }
            samples[id] = (received, Date(), item.speed, item.started)
            browser[id] = item
            if isNew { onStarted?(item) }
        } else {
            browser[id] = nil
            samples[id] = nil
        }
        publish(files: active.filter { !$0.id.hasPrefix("browser-") })
    }

    private func schedule() {
        guard !pending else { return }
        pending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            MainActor.assumeIsolated {
                self?.pending = false
                self?.scan(initial: false)
            }
        }
    }

    private func scan(initial: Bool) {
        let keys: [URLResourceKey] = [.fileSizeKey, .totalFileAllocatedSizeKey, .creationDateKey, .contentModificationDateKey, .isDirectoryKey, .addedToDirectoryDateKey]
        guard let entries = try? FileManager.default.contentsOfDirectory(at: Self.folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else { return }
        let now = Date()
        var names: Set<String> = []
        var partials: [Active] = []
        var landed: [Finished] = []
        for url in entries {
            let name = url.lastPathComponent
            names.insert(name)
            let values = try? url.resourceValues(forKeys: Set(keys))
            let ext = url.pathExtension.lowercased()
            if let browserName = Self.partial[ext] {
                var bytes = Int64(values?.fileSize ?? 0)
                var total: Int64?
                if ext == "download" {
                    (bytes, total) = Self.safariProgress(url)
                }
                let display = Self.displayName(url)
                let started = samples[url.path]?.started ?? values?.creationDate ?? now
                var speed = 0.0
                if let sample = samples[url.path] {
                    let elapsed = now.timeIntervalSince(sample.date)
                    let instant = elapsed > 0.2 ? Double(bytes - sample.bytes) / elapsed : sample.speed
                    speed = sample.speed == 0 ? instant : sample.speed * 0.65 + instant * 0.35
                }
                samples[url.path] = (bytes, now, speed, started)
                partials.append(Active(id: url.path, name: display, bytes: bytes, total: total, speed: max(speed, 0),
                                       source: browserName, started: started))
            } else if !initial, !known.contains(name) {
                let added = values?.addedToDirectoryDate ?? values?.creationDate ?? now
                let downloaded = recent[name] != nil || getxattr(url.path, "com.apple.quarantine", nil, 0, 0, 0) >= 0
                if now.timeIntervalSince(added) < 120, downloaded {
                    landed.append(Finished(url: url, name: name, size: Int64(values?.fileSize ?? values?.totalFileAllocatedSize ?? 0), date: now))
                }
            } else if initial {
                let modified = values?.addedToDirectoryDate ?? values?.contentModificationDate ?? .distantPast
                if now.timeIntervalSince(modified) < 86_400, values?.isDirectory != true {
                    landed.append(Finished(url: url, name: name, size: Int64(values?.fileSize ?? 0), date: modified))
                }
            }
        }
        for gone in samples.keys where !gone.hasPrefix("browser-") && !partials.contains(where: { $0.id == gone }) {
            samples[gone] = nil
        }
        for item in partials { recent[item.name] = now }
        recent = recent.filter { now.timeIntervalSince($0.value) < 600 }
        let previous = Set(active.map(\.id))
        known = names
        publish(files: partials)
        for item in partials where !previous.contains(item.id) && !initial { onStarted?(item) }
        if initial {
            finished = Array(landed.sorted { $0.date > $1.date }.prefix(6))
        } else {
            for item in landed {
                finished.removeAll { $0.url == item.url }
                finished.insert(item, at: 0)
                onFinished?(item)
            }
            if finished.count > 12 { finished = Array(finished.prefix(12)) }
        }
        updatePolling()
    }

    private func publish(files: [Active]) {
        var merged = files
        for item in browser.values {
            if let index = merged.firstIndex(where: { $0.name == item.name || ($0.source == "Chrome" && $0.id.contains("Unconfirmed")) }) {
                merged[index] = item
            } else {
                merged.append(item)
            }
        }
        merged.sort { $0.started < $1.started }
        if merged != active { active = merged }
        updatePolling()
    }

    private func updatePolling() {
        if active.isEmpty {
            poll?.invalidate()
            poll = nil
        } else if poll == nil {
            poll = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.scan(initial: false) }
            }
        }
    }

    private static func displayName(_ url: URL) -> String {
        var name = url.deletingPathExtension().lastPathComponent
        if name.hasPrefix("Unconfirmed ") || name.hasPrefix(".com.google.Chrome") {
            name = Phrase("Download", ru: "Загрузка", uk: "Завантаження", fr: "Téléchargement").text(Suite.shared.language)
        }
        return name
    }

    /// Safari keeps the partial file and its progress inside a .download bundle.
    private static func safariProgress(_ bundle: URL) -> (Int64, Int64?) {
        let info = bundle.appendingPathComponent("Info.plist")
        if let data = try? Data(contentsOf: info),
           let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
            let done = (plist["DownloadEntryProgressBytesSoFar"] as? NSNumber)?.int64Value
            let total = (plist["DownloadEntryProgressTotalToLoad"] as? NSNumber)?.int64Value
            if let done { return (done, total.flatMap { $0 > 0 ? $0 : nil }) }
        }
        var bytes: Int64 = 0
        if let items = try? FileManager.default.contentsOfDirectory(at: bundle, includingPropertiesForKeys: [.fileSizeKey]) {
            for item in items where item.lastPathComponent != "Info.plist" {
                bytes += Int64((try? item.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            }
        }
        return (bytes, nil)
    }
}
