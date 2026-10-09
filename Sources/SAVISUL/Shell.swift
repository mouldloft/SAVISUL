import AppKit
import Carbon.HIToolbox

enum Shell {
    struct Output {
        var status: Int32
        var text: String
    }

    /// Runs a tool synchronously. Call it off the main thread.
    @discardableResult
    static func run(_ path: String, _ arguments: [String], timeout: TimeInterval = 20) -> Output? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: watchdog)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()
        return Output(status: process.terminationStatus, text: String(data: data, encoding: .utf8) ?? "")
    }
}

enum AdminError: Error, Equatable {
    case cancelled
    case failed(String)
}

/// Runs one shell command as root after macOS shows its own password dialog.
@MainActor
enum Admin {
    static func run(_ command: String, prompt: String) -> Result<Void, AdminError> {
        let source = "do shell script \"\(escape(command))\" with prompt \"\(escape(prompt))\" with administrator privileges"
        guard let script = NSAppleScript(source: source) else { return .failure(.failed("AppleScript")) }
        NSApp.activate()
        var error: NSDictionary?
        script.executeAndReturnError(&error)
        guard let error else { return .success(()) }
        let code = error[NSAppleScript.errorNumber] as? Int ?? 0
        if code == -128 { return .failure(.cancelled) }
        let message = error[NSAppleScript.errorMessage] as? String ?? "error \(code)"
        return .failure(.failed(message))
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}

/// ⌃⌥S opens the panel.
@MainActor
final class HotKey {
    static var onPress: (() -> Void)?

    func register() -> Bool {
        HotKeyCenter.shared.register("panel", .control(kVK_ANSI_S)) { HotKey.onPress?() }
    }
}
