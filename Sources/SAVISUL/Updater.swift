import AppKit
import Foundation
import Security

/// Updates SAVISUL in place from its GitHub releases: no new download to open, no Terminal. The new build must carry
/// SAVISUL's own signature, and since it is the same signature, macOS keeps every permission the old build had.
@MainActor @Observable
final class Updater {
    static let shared = Updater()

    enum State: Equatable {
        case idle, checking, upToDate, failed
        case available(String)
        case downloading(String)
        case installing(String)
    }

    private(set) var state: State = .idle
    @ObservationIgnored private var archive: URL?
    @ObservationIgnored private var timer: Timer?

    /// Only a build signed with SAVISUL's certificate may replace this one.
    nonisolated static let requirement = #"identifier "com.savisul.menu" and certificate root = H"dad7d8d7971ef0d2e532e257cfceaaefa76feb89""#
    private static let feed = URL(string: "https://api.github.com/repos/mouldloft/SAVISUL/releases/latest")!

    var current: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0" }

    var busy: Bool {
        switch state {
        case .checking, .downloading, .installing: true
        default: false
        }
    }

    func start() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            MainActor.assumeIsolated { self?.check(quietly: true) }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check(quietly: true) }
        }
    }

    func check(quietly: Bool = false) {
        guard !busy else { return }
        if !quietly { state = .checking }
        var request = URLRequest(url: Self.feed, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: request) { data, _, _ in
            let release = data.flatMap { try? JSONDecoder().decode(Release.self, from: $0) }
            DispatchQueue.main.async { MainActor.assumeIsolated { self.received(release, quietly: quietly) } }
        }.resume()
    }

    private func received(_ release: Release?, quietly: Bool) {
        guard let release, let zip = release.assets.first(where: { $0.name.hasSuffix(".zip") }) else {
            if !quietly { state = .failed }
            return
        }
        let version = release.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        guard Self.isNewer(version, than: current) else {
            if !quietly || state == .checking { state = .upToDate }
            return
        }
        archive = URL(string: zip.browser_download_url)
        state = .available(version)
        // Announced once per version; Settings keeps the button after that.
        guard UserDefaults.standard.string(forKey: "updateAnnounced") != version else { return }
        UserDefaults.standard.set(version, forKey: "updateAnnounced")
        Suite.shared.notify(IslandNotice(symbol: "arrow.down.circle", tint: Palette.accent, title: UpdatePhrases.available.text + " " + version,
                                         detail: UpdatePhrases.detail.text, style: .warning, duration: 14,
                                         actionTitle: UpdatePhrases.update.text, action: { Updater.shared.install() }))
    }

    nonisolated static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0) ?? 0 }, b = current.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(a.count, b.count) {
            let left = index < a.count ? a[index] : 0, right = index < b.count ? b[index] : 0
            if left != right { return left > right }
        }
        return false
    }

    func install() {
        guard case let .available(version) = state, let archive else { return }
        state = .downloading(version)
        URLSession.shared.downloadTask(with: archive) { file, _, _ in
            // The downloaded file is gone once this returns, so it is unpacked here.
            let work = FileManager.default.temporaryDirectory.appendingPathComponent("savisul-update-\(UUID().uuidString)")
            var app: URL?
            if let file, (try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)) != nil {
                let zip = work.appendingPathComponent("update.zip")
                if (try? FileManager.default.moveItem(at: file, to: zip)) != nil, Self.run("/usr/bin/ditto", ["-x", "-k", zip.path, work.path]) {
                    app = Self.findApp(in: work)
                }
            }
            let verified = app.map(Self.isSAVISUL) ?? false
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self.unpacked(verified ? app : nil, version: version) }
            }
        }.resume()
    }

    private func unpacked(_ app: URL?, version: String) {
        guard let app else {
            state = .failed
            return
        }
        state = .installing(version)
        // A helper swaps the bundle once SAVISUL has quit, then opens the new one; if the swap fails the old one returns.
        let destination = Bundle.main.bundleURL.path
        let script = """
        while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.2; done
        /usr/bin/xattr -dr com.apple.quarantine \(quote(app.path)) 2>/dev/null
        rm -rf \(quote(destination + ".old"))
        if mv \(quote(destination)) \(quote(destination + ".old")) && /usr/bin/ditto \(quote(app.path)) \(quote(destination)); then
          rm -rf \(quote(destination + ".old"))
        else
          rm -rf \(quote(destination)); mv \(quote(destination + ".old")) \(quote(destination))
        fi
        /usr/bin/open \(quote(destination))
        """
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/zsh")
        helper.arguments = ["-c", script]
        guard (try? helper.run()) != nil else {
            state = .failed
            return
        }
        NSApp.terminate(nil)
    }

    private func quote(_ path: String) -> String { "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    nonisolated private static func findApp(in folder: URL) -> URL? {
        let items = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        while let item = items?.nextObject() as? URL {
            if item.lastPathComponent == "SAVISUL.app" { return item }
        }
        return nil
    }

    /// The bundle is SAVISUL and is signed with SAVISUL's certificate, unaltered.
    nonisolated static func isSAVISUL(_ app: URL) -> Bool {
        var code: SecStaticCode?, requirement: SecRequirement?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code,
              SecRequirementCreateWithString(Self.requirement as CFString, [], &requirement) == errSecSuccess, let requirement else { return false }
        return SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate), requirement) == errSecSuccess
    }

    nonisolated private static func run(_ tool: String, _ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        guard (try? process.run()) != nil else { return false }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    private struct Release: Decodable {
        let tag_name: String
        let assets: [Asset]
        struct Asset: Decodable {
            let name: String
            let browser_download_url: String
        }
    }
}

enum UpdatePhrases {
    static let title = Phrase("Updates", ru: "Обновления", uk: "Оновлення", fr: "Mises à jour")
    static let available = Phrase("SAVISUL is out:", ru: "Вышел SAVISUL", uk: "Вийшов SAVISUL", fr: "SAVISUL est sorti :")
    static let detail = Phrase("Installs in place and keeps your settings and permissions.",
                               ru: "Встанет на место старого, настройки и разрешения сохранятся.",
                               uk: "Стане на місце старого, налаштування й дозволи збережуться.",
                               fr: "S’installe à la place de l’ancien, en gardant réglages et autorisations.")
    static let update = Phrase("Update", ru: "Обновить", uk: "Оновити", fr: "Mettre à jour")
    static let check = Phrase("Check", ru: "Проверить", uk: "Перевірити", fr: "Vérifier")
    static let checking = Phrase("Checking…", ru: "Проверяю…", uk: "Перевіряю…", fr: "Vérification…")
    static let upToDate = Phrase("You have the latest version", ru: "У вас последняя версия", uk: "У вас остання версія",
                                 fr: "Vous avez la dernière version")
    static let downloading = Phrase("Downloading", ru: "Скачиваю", uk: "Завантажую", fr: "Téléchargement de")
    static let installing = Phrase("Installing — SAVISUL will reopen", ru: "Устанавливаю — SAVISUL откроется заново",
                                   uk: "Встановлюю — SAVISUL відкриється знову", fr: "Installation — SAVISUL va se rouvrir")
    static let failed = Phrase("Couldn’t update. Try again later or download it from savisul.com.",
                               ru: "Не получилось обновить. Попробуйте позже или скачайте с savisul.com.",
                               uk: "Не вдалося оновити. Спробуйте пізніше або завантажте з savisul.com.",
                               fr: "Mise à jour impossible. Réessayez plus tard ou téléchargez-le sur savisul.com.")
    static let version = Phrase("Version", ru: "Версия", uk: "Версія", fr: "Version")
}
