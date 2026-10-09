import AppKit
import Observation
import UniformTypeIdentifiers

struct UtilityItem: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var target: String
    var isCommand: Bool
}

enum BuiltinUtility: String, CaseIterable, Identifiable {
    case activity, terminal, settings, disk, displayOff, copyIP, hiddenFiles

    var id: String { rawValue }

    var title: Copy {
        switch self {
        case .activity: .uActivity
        case .terminal: .uTerminal
        case .settings: .uSettings
        case .disk: .uDisk
        case .displayOff: .uDisplayOff
        case .copyIP: .uCopyIP
        case .hiddenFiles: .uHidden
        }
    }

    var appPath: String? {
        switch self {
        case .activity: "/System/Applications/Utilities/Activity Monitor.app"
        case .terminal: "/System/Applications/Utilities/Terminal.app"
        case .settings: "/System/Applications/System Settings.app"
        case .disk: "/System/Applications/Utilities/Disk Utility.app"
        default: nil
        }
    }

    var symbol: String {
        switch self {
        case .displayOff: "moon.zzz"
        case .copyIP: "network"
        case .hiddenFiles: "eye"
        default: "app"
        }
    }
}

enum UtilityOutcome {
    case done(String)
    case failed(String, String)
    case couldNotOpen(String)
    case ipCopied(String)
    case noAddress
    case hiddenFiles(Bool)
    case silent
}

@MainActor
@Observable
final class UtilityStore {
    var items: [UtilityItem] = []
    var adding = false
    var draftName = ""
    var draftTarget = ""
    var draftIsCommand = false
    var running: Set<UUID> = []
    var hiddenFilesVisible = false

    @ObservationIgnored private let fileURL: URL

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SAVISUL", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        fileURL = support.appendingPathComponent("utilities.json")
        if let data = try? Data(contentsOf: fileURL), let saved = try? JSONDecoder().decode([UtilityItem].self, from: data) {
            items = saved
        }
    }

    var canAdd: Bool {
        !draftName.trimmingCharacters(in: .whitespaces).isEmpty && !draftTarget.trimmingCharacters(in: .whitespaces).isEmpty
    }

    func add() {
        guard canAdd else { return }
        items.append(UtilityItem(name: draftName.trimmingCharacters(in: .whitespaces),
                                 target: draftTarget.trimmingCharacters(in: .whitespaces),
                                 isCommand: draftIsCommand))
        draftName = ""
        draftTarget = ""
        draftIsCommand = false
        adding = false
        save()
    }

    func remove(_ id: UUID) {
        items.removeAll { $0.id == id }
        save()
    }

    func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        draftTarget = url.path
        draftIsCommand = false
        if draftName.trimmingCharacters(in: .whitespaces).isEmpty {
            draftName = (FileManager.default.displayName(atPath: url.path) as NSString).deletingPathExtension
        }
    }

    func run(_ builtin: BuiltinUtility, completion: @escaping (UtilityOutcome) -> Void) {
        if let path = builtin.appPath {
            open(path: path, name: builtin.rawValue, completion: completion)
            return
        }
        switch builtin {
        case .displayOff:
            DispatchQueue.global(qos: .userInitiated).async { Shell.run("/usr/bin/pmset", ["displaysleepnow"], timeout: 5) }
            completion(.silent)
        case .copyIP:
            guard let address = Self.localIPv4() else {
                completion(.noAddress)
                return
            }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(address, forType: .string)
            completion(.ipCopied(address))
        case .hiddenFiles:
            let show = !hiddenFilesVisible
            hiddenFilesVisible = show
            DispatchQueue.global(qos: .userInitiated).async {
                Shell.run("/usr/bin/defaults", ["write", "com.apple.finder", "AppleShowAllFiles", "-bool", show ? "true" : "false"])
                Shell.run("/usr/bin/killall", ["Finder"])
            }
            completion(.hiddenFiles(show))
        default:
            completion(.silent)
        }
    }

    func refreshHiddenFiles() {
        DispatchQueue.global(qos: .utility).async {
            let output = Shell.run("/usr/bin/defaults", ["read", "com.apple.finder", "AppleShowAllFiles"], timeout: 5)
            let value = output?.text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
            let visible = ["1", "yes", "true"].contains(value)
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    if self?.hiddenFilesVisible != visible { self?.hiddenFilesVisible = visible }
                }
            }
        }
    }

    func launch(_ item: UtilityItem, completion: @escaping (UtilityOutcome) -> Void) {
        guard item.isCommand else {
            open(path: item.target, name: item.name, completion: completion)
            return
        }
        guard !running.contains(item.id) else { return }
        running.insert(item.id)
        let id = item.id
        DispatchQueue.global(qos: .userInitiated).async {
            let output = Shell.run("/bin/zsh", ["-lc", item.target], timeout: 120)
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    self?.running.remove(id)
                    guard let output else {
                        completion(.failed(item.name, "zsh"))
                        return
                    }
                    if output.status == 0 {
                        completion(.done(item.name))
                    } else {
                        let line = output.text.split(separator: "\n").last.map(String.init) ?? "exit \(output.status)"
                        completion(.failed(item.name, line))
                    }
                }
            }
        }
    }

    private func open(path: String, name: String, completion: @escaping (UtilityOutcome) -> Void) {
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            completion(.couldNotOpen(name))
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            DispatchQueue.main.async {
                completion(error == nil ? .silent : .couldNotOpen(name))
            }
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    static func localIPv4() -> String? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return nil }
        defer { freeifaddrs(list) }
        var fallback: String?
        for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(entry.pointee.ifa_flags)
            guard let address = entry.pointee.ifa_addr, address.pointee.sa_family == UInt8(AF_INET),
                  flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0 else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else {
                continue
            }
            let ip = String(cString: host)
            if String(cString: entry.pointee.ifa_name).hasPrefix("en") { return ip }
            if fallback == nil { fallback = ip }
        }
        return fallback
    }
}
