import AppKit
import Observation
import SwiftUI

struct NowPlayingItem: Equatable {
    var title: String
    var artist: String
    var album: String
    var duration: Double
    var elapsed: Double
    var rate: Double
    var stamp: Date
    var playing: Bool
    var pid: pid_t

    var key: String { "\(artist)\u{1F}\(title)" }

    func position(at date: Date = Date()) -> Double {
        guard playing, rate > 0 else { return min(elapsed, duration > 0 ? duration : elapsed) }
        let value = elapsed + date.timeIntervalSince(stamp) * rate
        return duration > 0 ? min(max(value, 0), duration) : max(value, 0)
    }

    var progress: Double { duration > 0 ? position() / duration : 0 }
}

/// System Now Playing for every player (Music, Spotify, browsers, podcasts), read through a helper
/// process because MediaRemote ignores apps outside Apple's own since macOS 15.4.
@MainActor
@Observable
final class NowPlaying {
    private(set) var item: NowPlayingItem?
    private(set) var artwork: NSImage?
    private(set) var tint = Color(red: 0.86, green: 0.78, blue: 0.64)
    private(set) var appPath: String?
    private(set) var available = true

    var playing: Bool { item?.playing == true }
    var appName: String? {
        appPath.map { FileManager.default.displayName(atPath: $0).replacingOccurrences(of: ".app", with: "") }
    }

    @ObservationIgnored var onTrackChange: ((NowPlayingItem) -> Void)?
    @ObservationIgnored private var process: Process?
    @ObservationIgnored private var input: FileHandle?
    @ObservationIgnored private var buffer = Data()
    @ObservationIgnored private var artworkID: String?
    @ObservationIgnored private var restarts = 0
    @ObservationIgnored private var wanted = false

    func start() {
        wanted = true
        launch()
    }

    func stop() {
        wanted = false
        process?.terminationHandler = nil
        process?.terminate()
        process = nil
        input = nil
        item = nil
    }

    func toggle() { send("toggle") }
    func next() { send("next") }
    func previous() { send("previous") }

    func seek(to fraction: Double) {
        guard let item, item.duration > 0 else { return }
        let seconds = max(0, min(item.duration, fraction * item.duration))
        self.item?.elapsed = seconds
        self.item?.stamp = Date()
        send("seek \(seconds)")
    }

    func openPlayer() {
        guard let appPath else { return }
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: appPath), configuration: NSWorkspace.OpenConfiguration())
    }

    /// Panel renders (--dump-panels): shows a sample track without starting the media helper.
    func preview(_ sample: NowPlayingItem, artwork: NSImage?, tint: Color, appPath: String?) {
        item = sample
        self.artwork = artwork
        self.tint = tint
        self.appPath = appPath
    }

    private func send(_ command: String) {
        guard let input, let data = (command + "\n").data(using: .utf8) else { return }
        try? input.write(contentsOf: data)
    }

    private static var library: URL? {
        let bundled = Bundle.main.privateFrameworksURL?.appendingPathComponent("libSAVISULMedia.dylib")
        if let bundled, FileManager.default.fileExists(atPath: bundled.path) { return bundled }
        return nil
    }

    private func launch() {
        guard wanted, process == nil, let library = Self.library else {
            if Self.library == nil { available = false }
            return
        }
        let script = """
        use DynaLoader; my $h = DynaLoader::dl_load_file($ARGV[0], 0) or exit 3;
        my $s = DynaLoader::dl_find_symbol($h, "savisul_media_run") or exit 4;
        my $f = DynaLoader::dl_install_xsub("main::run", $s); &$f();
        """
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        task.arguments = ["-e", script, library.path]
        let stdout = Pipe()
        let stdin = Pipe()
        task.standardOutput = stdout
        task.standardInput = stdin
        task.standardError = FileHandle.nullDevice
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.receive(chunk) } }
        }
        task.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.ended() } }
        }
        do {
            try task.run()
            process = task
            input = stdin.fileHandleForWriting
            available = true
        } catch {
            available = false
        }
    }

    private func ended() {
        process = nil
        input = nil
        guard wanted else { return }
        restarts += 1
        if restarts > 6 {
            available = false
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(min(restarts * 3, 15))) { [weak self] in
            MainActor.assumeIsolated { self?.launch() }
        }
    }

    private func receive(_ chunk: Data) {
        buffer.append(chunk)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            apply(object)
        }
    }

    private func apply(_ object: [String: Any]) {
        if object["ready"] != nil {
            restarts = 0
            return
        }
        if object["error"] != nil {
            available = false
            return
        }
        let title = object["title"] as? String ?? ""
        let pid = pid_t(object["pid"] as? Int ?? 0)
        guard !title.isEmpty else {
            if item != nil { item = nil }
            artwork = nil
            artworkID = nil
            appPath = nil
            return
        }
        let rate = object["rate"] as? Double ?? 0
        let playingFlag = object["playing"] as? Bool ?? false
        let next = NowPlayingItem(
            title: title,
            artist: object["artist"] as? String ?? "",
            album: object["album"] as? String ?? "",
            duration: object["duration"] as? Double ?? 0,
            elapsed: object["elapsed"] as? Double ?? 0,
            rate: rate,
            stamp: Date(timeIntervalSince1970: object["timestamp"] as? Double ?? Date().timeIntervalSince1970),
            playing: playingFlag || rate > 0,
            pid: pid
        )
        let changedTrack = item?.key != next.key
        if item != next { item = next }
        if pid > 0, appPath == nil || changedTrack {
            appPath = NSRunningApplication(processIdentifier: pid)?.bundleURL?.path ?? RunningApps.bundlePath(pid: pid)
        }
        let newArtwork = object["artworkID"] as? String
        if let encoded = object["artwork"] as? String, let data = Data(base64Encoded: encoded), let image = NSImage(data: data) {
            artwork = image
            artworkID = newArtwork
            tint = Self.tint(of: image)
        } else if newArtwork == nil, changedTrack {
            artwork = nil
            artworkID = nil
            tint = Palette.accent
        }
        if changedTrack { onTrackChange?(next) }
    }

    /// Average color of the artwork, lifted so it reads on black.
    static func tint(of image: NSImage) -> Color {
        var rect = NSRect(x: 0, y: 0, width: 12, height: 12)
        guard let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return Palette.accent }
        let side = 12
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard let context = CGContext(data: &pixels, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return Palette.accent }
        context.interpolationQuality = .medium
        context.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
        var best = (r: 0.0, g: 0.0, b: 0.0, score: -1.0)
        var sum = (r: 0.0, g: 0.0, b: 0.0)
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let r = Double(pixels[index]) / 255, g = Double(pixels[index + 1]) / 255, b = Double(pixels[index + 2]) / 255
            sum.r += r; sum.g += g; sum.b += b
            let high = max(r, g, b), low = min(r, g, b)
            let saturation = high > 0 ? (high - low) / high : 0
            let score = saturation * 0.7 + high * 0.3
            if score > best.score { best = (r, g, b, score) }
        }
        let count = Double(side * side)
        var color = best.score > 0.35 ? (best.r, best.g, best.b) : (sum.r / count, sum.g / count, sum.b / count)
        let brightness = max(color.0, color.1, color.2)
        if brightness < 0.62 {
            let lift = 0.62 / max(brightness, 0.05)
            color = (min(color.0 * lift, 1), min(color.1 * lift, 1), min(color.2 * lift, 1))
        }
        let mix = 0.18
        return Color(red: color.0 * (1 - mix) + mix, green: color.1 * (1 - mix) + mix, blue: color.2 * (1 - mix) + mix)
    }
}
