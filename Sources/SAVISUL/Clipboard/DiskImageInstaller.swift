import AppKit

/// When a disk image with an app mounts, the island offers to install it: copy to Applications,
/// replace the old version through the Trash, eject the image and throw the .dmg away.
@MainActor
final class DiskImageInstaller {
    private var observer: NSObjectProtocol?
    private var busy = false

    func enable(_ on: Bool) {
        if on, observer == nil {
            observer = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didMountNotification, object: nil, queue: .main) { note in
                guard let url = note.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL else { return }
                MainActor.assumeIsolated { Suite.shared.clipboard.installer.mounted(url) }
            }
        } else if !on, let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            self.observer = nil
        }
    }

    fileprivate func mounted(_ volume: URL) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let image = Self.imagePath(for: volume), let app = Self.app(in: volume) else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { Suite.shared.clipboard.installer.offer(app: app, volume: volume, image: image) }
            }
        }
    }

    /// The .dmg behind a mounted volume, or nil for real disks.
    nonisolated static func imagePath(for volume: URL) -> URL? {
        guard let output = Shell.run("/usr/bin/hdiutil", ["info", "-plist"], timeout: 8), output.status == 0,
              let data = output.text.data(using: .utf8),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let images = plist["images"] as? [[String: Any]] else { return nil }
        let mount = volume.standardizedFileURL.path
        for image in images {
            let entities = image["system-entities"] as? [[String: Any]] ?? []
            if entities.contains(where: { ($0["mount-point"] as? String).map { URL(fileURLWithPath: $0).standardizedFileURL.path } == mount }),
               let path = image["image-path"] as? String {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }

    nonisolated static func app(in volume: URL) -> URL? {
        let items = (try? FileManager.default.contentsOfDirectory(at: volume, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        let apps = items.filter { $0.pathExtension == "app" }
        return apps.first { !$0.lastPathComponent.localizedCaseInsensitiveContains("uninstall") } ?? apps.first
    }

    private func offer(app: URL, volume: URL, image: URL) {
        let name = app.deletingPathExtension().lastPathComponent
        Suite.shared.notify(IslandNotice(symbol: "shippingbox.fill", tint: Palette.accent, title: InstallPhrases.install(name),
                                         detail: image.lastPathComponent, image: NSWorkspace.shared.icon(forFile: app.path),
                                         duration: 14, actionTitle: InstallPhrases.installButton.text,
                                         action: { Suite.shared.clipboard.installer.install(app: app, volume: volume, image: image) }))
    }

    func install(app: URL, volume: URL, image: URL) {
        guard !busy else { return }
        busy = true
        let name = app.deletingPathExtension().lastPathComponent
        let icon = NSWorkspace.shared.icon(forFile: app.path)
        let writable = FileManager.default.isWritableFile(atPath: "/Applications")
        let folder = writable ? URL(fileURLWithPath: "/Applications", isDirectory: true)
            : FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
        let destination = folder.appendingPathComponent(app.lastPathComponent)
        let running = NSWorkspace.shared.runningApplications.filter { $0.bundleURL?.standardizedFileURL == destination.standardizedFileURL }
        running.forEach { $0.terminate() }
        Suite.shared.notify(IslandNotice(symbol: "arrow.down.app.fill", tint: Palette.accent, title: InstallPhrases.installing(name),
                                         detail: folder.path, image: icon, duration: 30))
        let trashImage = Suite.shared.settings.dmgTrash && Self.isDownload(image)
        DispatchQueue.global(qos: .userInitiated).async {
            for _ in 0..<50 where running.contains(where: { !$0.isTerminated }) { usleep(100_000) }
            var failure: String?
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.trashItem(at: destination, resultingItemURL: nil)
                }
                let copy = Shell.run("/usr/bin/ditto", [app.path, destination.path], timeout: 600)
                if copy?.status != 0 { failure = copy?.text.isEmpty == false ? copy?.text : "ditto" }
            } catch {
                failure = error.localizedDescription
            }
            if failure == nil {
                if (try? NSWorkspace.shared.unmountAndEjectDevice(at: volume)) == nil {
                    _ = Shell.run("/usr/bin/hdiutil", ["detach", volume.path, "-quiet"], timeout: 20)
                }
                if trashImage { try? FileManager.default.trashItem(at: image, resultingItemURL: nil) }
            }
            let error = failure
            DispatchQueue.main.async {
                MainActor.assumeIsolated { Suite.shared.clipboard.installer.finished(name: name, at: destination, error: error) }
            }
        }
    }

    private func finished(name: String, at destination: URL, error: String?) {
        busy = false
        let icon = NSWorkspace.shared.icon(forFile: destination.path)
        if let error {
            Suite.shared.notify(IslandNotice(symbol: "exclamationmark.triangle.fill", tint: Palette.danger, title: InstallPhrases.failed(name),
                                             detail: error.trimmingCharacters(in: .whitespacesAndNewlines), style: .warning, duration: 6))
            return
        }
        Suite.shared.notify(IslandNotice(symbol: "checkmark.seal.fill", tint: Palette.positive, title: InstallPhrases.installed(name),
                                         detail: destination.deletingLastPathComponent().path, image: icon, style: .success, duration: 8,
                                         actionTitle: Phrases.open.text, action: {
            NSWorkspace.shared.openApplication(at: destination, configuration: NSWorkspace.OpenConfiguration())
        }))
    }

    nonisolated private static func isDownload(_ url: URL) -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = url.standardizedFileURL.path
        return path.hasPrefix(home + "/Downloads/") || path.hasPrefix(home + "/Desktop/")
    }
}

enum InstallPhrases {
    static let installButton = Phrase("Install", ru: "Установить", uk: "Встановити", fr: "Installer")
    @MainActor static func install(_ name: String) -> String {
        Phrase("Install %@?", ru: "Установить %@?", uk: "Встановити %@?", fr: "Installer %@ ?")(name)
    }
    @MainActor static func installing(_ name: String) -> String {
        Phrase("Installing %@…", ru: "Устанавливаю %@…", uk: "Встановлюю %@…", fr: "Installation de %@…")(name)
    }
    @MainActor static func installed(_ name: String) -> String {
        Phrase("%@ is installed", ru: "%@ установлен", uk: "%@ встановлено", fr: "%@ est installé")(name)
    }
    @MainActor static func failed(_ name: String) -> String {
        Phrase("Couldn’t install %@", ru: "Не удалось установить %@", uk: "Не вдалося встановити %@", fr: "Échec de l’installation de %@")(name)
    }
}
