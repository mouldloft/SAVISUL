import Foundation
import Observation

/// Time-synced lyrics from lrclib.net, cached on disk per track.
@MainActor
@Observable
final class Lyrics {
    struct Line: Equatable {
        var time: Double
        var text: String
    }

    enum State: Equatable { case idle, loading, synced, plain, missing }

    private(set) var lines: [Line] = []
    private(set) var plain: String?
    private(set) var state: State = .idle
    @ObservationIgnored private var key: String?
    @ObservationIgnored private var task: Task<Void, Never>?

    func load(for item: NowPlayingItem?) {
        guard let item, !item.title.isEmpty else {
            reset()
            return
        }
        guard item.key != key else { return }
        reset()
        key = item.key
        guard !item.artist.isEmpty, item.duration == 0 || (20...1200).contains(item.duration) else {
            state = .missing
            return
        }
        state = .loading
        let request = (title: item.title, artist: item.artist, album: item.album, duration: item.duration)
        let wanted = item.key
        task = Task { [weak self] in
            let found = await Self.fetch(title: request.title, artist: request.artist, album: request.album, duration: request.duration)
            guard let self, self.key == wanted else { return }
            self.apply(found)
        }
    }

    /// Panel renders (--dump-panels): shows these lines as synced lyrics without a lookup.
    func preview(_ sample: [Line]) {
        task?.cancel()
        key = nil
        lines = sample
        state = .synced
    }

    /// The line being sung and the one after it.
    func lines(at position: Double) -> (current: String?, next: String?, progress: Double) {
        Self.sung(lines, at: position)
    }

    /// Which line is being sung at `position`, and how far through it we are.
    nonisolated static func sung(_ lines: [Line], at position: Double) -> (current: String?, next: String?, progress: Double) {
        guard !lines.isEmpty else { return (nil, nil, 0) }
        var index = -1
        var low = 0, high = lines.count - 1
        while low <= high {
            let mid = (low + high) / 2
            if lines[mid].time <= position + 0.25 { index = mid; low = mid + 1 } else { high = mid - 1 }
        }
        guard index >= 0 else { return (nil, lines.first?.text, 0) }
        let current = lines[index]
        let following = index + 1 < lines.count ? lines[index + 1] : nil
        let span = max((following?.time ?? current.time + 4) - current.time, 0.5)
        let progress = min(max((position - current.time) / span, 0), 1)
        return (current.text, following?.text, progress)
    }

    private func reset() {
        task?.cancel()
        task = nil
        key = nil
        lines = []
        plain = nil
        state = .idle
    }

    private func apply(_ found: Payload?) {
        guard let found else {
            state = .missing
            return
        }
        if let synced = found.synced, !synced.isEmpty {
            lines = Self.parse(synced)
        }
        plain = found.plain
        state = !lines.isEmpty ? .synced : (plain?.isEmpty == false ? .plain : .missing)
    }

    struct Payload: Codable {
        var synced: String?
        var plain: String?
    }

    nonisolated static func parse(_ text: String) -> [Line] {
        var result: [Line] = []
        let pattern = try! NSRegularExpression(pattern: #"\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\]"#)
        for raw in text.components(separatedBy: .newlines) {
            let range = NSRange(raw.startIndex..., in: raw)
            let matches = pattern.matches(in: raw, range: range)
            guard let last = matches.last, let tail = Range(last.range, in: raw) else { continue }
            let words = raw[tail.upperBound...].trimmingCharacters(in: .whitespaces)
            for match in matches {
                func group(_ index: Int) -> String? {
                    guard let r = Range(match.range(at: index), in: raw) else { return nil }
                    return String(raw[r])
                }
                let minutes = Double(group(1) ?? "0") ?? 0
                let seconds = Double(group(2) ?? "0") ?? 0
                var fraction = 0.0
                if let digits = group(3) { fraction = (Double(digits) ?? 0) / pow(10, Double(digits.count)) }
                result.append(Line(time: minutes * 60 + seconds + fraction, text: words.isEmpty ? "♪" : words))
            }
        }
        return result.sorted { $0.time < $1.time }
    }

    nonisolated private static var cacheFolder: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("SAVISUL/lyrics", isDirectory: true)
    }

    nonisolated private static func cacheURL(title: String, artist: String) -> URL {
        let raw = "\(artist.lowercased())|\(title.lowercased())"
        var hash: UInt64 = 1469598103934665603
        for byte in raw.utf8 { hash = (hash ^ UInt64(byte)) &* 1099511628211 }
        return cacheFolder.appendingPathComponent(String(hash, radix: 16) + ".json")
    }

    nonisolated private static func fetch(title: String, artist: String, album: String, duration: Double) async -> Payload? {
        let cache = cacheURL(title: title, artist: artist)
        if let data = try? Data(contentsOf: cache), let payload = try? JSONDecoder().decode(Payload.self, from: data) {
            return payload.synced == nil && payload.plain == nil ? nil : payload
        }
        let cleanTitle = clean(title)
        var result: Payload?
        var components = URLComponents(string: "https://lrclib.net/api/get")!
        var query = [URLQueryItem(name: "track_name", value: cleanTitle), URLQueryItem(name: "artist_name", value: artist)]
        if !album.isEmpty { query.append(URLQueryItem(name: "album_name", value: album)) }
        if duration > 0 { query.append(URLQueryItem(name: "duration", value: String(Int(duration.rounded())))) }
        components.queryItems = query
        if let object = await request(components.url!) as? [String: Any] {
            result = payload(object)
        }
        if result?.synced == nil {
            var search = URLComponents(string: "https://lrclib.net/api/search")!
            search.queryItems = [URLQueryItem(name: "track_name", value: cleanTitle), URLQueryItem(name: "artist_name", value: artist)]
            if let list = await request(search.url!) as? [[String: Any]] {
                let ranked = list.sorted { lhs, rhs in
                    let a = abs((lhs["duration"] as? Double ?? 0) - duration)
                    let b = abs((rhs["duration"] as? Double ?? 0) - duration)
                    let syncedA = (lhs["syncedLyrics"] as? String)?.isEmpty == false
                    let syncedB = (rhs["syncedLyrics"] as? String)?.isEmpty == false
                    return syncedA != syncedB ? syncedA : a < b
                }
                if let best = ranked.first, duration == 0 || abs((best["duration"] as? Double ?? duration) - duration) < 8 {
                    result = payload(best) ?? result
                }
            }
        }
        if Task.isCancelled { return result }
        try? FileManager.default.createDirectory(at: cache.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(result ?? Payload()) { try? data.write(to: cache) }
        return result
    }

    nonisolated private static func payload(_ object: [String: Any]) -> Payload? {
        let synced = (object["syncedLyrics"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let plain = (object["plainLyrics"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        return synced == nil && plain == nil ? nil : Payload(synced: synced, plain: plain)
    }

    nonisolated private static func clean(_ title: String) -> String {
        var value = title
        for marker in [" - Remaster", " (Remaster", " [Remaster", " - Live", " (feat.", " [feat.", " (Official", " [Official"] {
            if let range = value.range(of: marker, options: .caseInsensitive) { value = String(value[..<range.lowerBound]) }
        }
        return value.trimmingCharacters(in: .whitespaces)
    }

    nonisolated private static func request(_ url: URL) async -> Any? {
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.setValue("SAVISUL/2.0 (macOS menu bar utility)", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }
}
