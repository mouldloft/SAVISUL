import AppKit
import Observation
import QuickLookThumbnailing

enum CaptureMode {
    case selection, window, screen
}

enum CaptureOutcome {
    case saved, cancelled, failed
}

struct CaptureResult: Equatable {
    var url: URL
    var isVideo: Bool
}

@MainActor
@Observable
final class CaptureService {
    var isRecording = false
    var recordingStart: Date?
    var last: CaptureResult?
    var thumbnail: NSImage?
    var justCopied = false

    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private var recorder: Process?
    @ObservationIgnored private var recorderInput: Pipe?
    @ObservationIgnored private var copiedReset: DispatchWorkItem?

    static var picturesFolder: URL {
        FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)[0].appendingPathComponent("SAVISUL", isDirectory: true)
    }

    static var moviesFolder: URL {
        FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask)[0].appendingPathComponent("SAVISUL", isDirectory: true)
    }

    func shoot(_ mode: CaptureMode, completion: @escaping (CaptureOutcome) -> Void) {
        let folder = Self.picturesFolder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("SAVISUL \(Self.stamp()).png")
        var arguments: [String] = switch mode {
        case .selection: ["-i", "-s"]
        case .window: ["-i", "-W"]
        case .screen: ["-m"]
        }
        arguments.append(url.path)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = arguments
        process.terminationHandler = { _ in
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    guard FileManager.default.fileExists(atPath: url.path) else {
                        completion(.cancelled)
                        return
                    }
                    self.last = CaptureResult(url: url, isVideo: false)
                    self.thumbnail = nil
                    self.makeThumbnail(for: url)
                    self.copy(url)
                    completion(.saved)
                }
            }
        }
        do {
            try process.run()
        } catch {
            completion(.failed)
        }
    }

    func startRecording(finished: @escaping (CaptureOutcome) -> Void) {
        guard recorder == nil else { return }
        let folder = Self.moviesFolder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("SAVISUL \(Self.stamp()).mov")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-v", "-k", url.path]
        let input = Pipe()
        process.standardInput = input
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let started = Date()
        process.terminationHandler = { _ in
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.recorder = nil
                    self.recorderInput = nil
                    self.isRecording = false
                    self.recordingStart = nil
                    self.onChange?()
                    if FileManager.default.fileExists(atPath: url.path) {
                        self.last = CaptureResult(url: url, isVideo: true)
                        self.thumbnail = nil
                        self.makeThumbnail(for: url)
                        finished(.saved)
                    } else {
                        finished(Date().timeIntervalSince(started) < 3 ? .failed : .cancelled)
                    }
                }
            }
        }
        do {
            try process.run()
        } catch {
            finished(.failed)
            return
        }
        recorder = process
        recorderInput = input
        isRecording = true
        recordingStart = Date()
        onChange?()
    }

    /// screencapture stops on any key from stdin; SIGINT is the fallback it also honours.
    func stopRecording() {
        guard let recorder else { return }
        try? recorderInput?.fileHandleForWriting.write(contentsOf: Data("q\n".utf8))
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if recorder.isRunning { recorder.interrupt() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
            if recorder.isRunning { recorder.terminate() }
        }
    }

    func openToolbar() {
        let url = URL(fileURLWithPath: "/System/Applications/Utilities/Screenshot.app")
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    func reveal() {
        guard let last else { return }
        NSWorkspace.shared.activateFileViewerSelecting([last.url])
    }

    func open() {
        guard let last else { return }
        NSWorkspace.shared.open(last.url)
    }

    func copyLast() {
        guard let last else { return }
        copy(last.url)
    }

    /// Screenshots saved by the browser extension become the latest capture as well.
    func adopt(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path), last?.url != url else { return }
        last = CaptureResult(url: url, isVideo: false)
        thumbnail = nil
        makeThumbnail(for: url)
        onChange?()
    }

    private func copy(_ url: URL) {
        let item = NSPasteboardItem()
        if url.pathExtension.lowercased() == "png", let data = try? Data(contentsOf: url) {
            item.setData(data, forType: .png)
            if let image = NSImage(data: data), let tiff = image.tiffRepresentation {
                item.setData(tiff, forType: .tiff)
            }
        }
        item.setString(url.absoluteString, forType: .fileURL)
        let board = NSPasteboard.general
        board.clearContents()
        board.writeObjects([item])
        justCopied = true
        copiedReset?.cancel()
        let reset = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.justCopied = false }
        }
        copiedReset = reset
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: reset)
    }

    private func makeThumbnail(for url: URL) {
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 96, height: 64), scale: 2,
                                                   representationTypes: .thumbnail)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
            guard let image = representation?.nsImage else { return }
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    if self?.last?.url == url { self?.thumbnail = image }
                }
            }
        }
    }

    private static func stamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return formatter.string(from: Date())
    }
}
