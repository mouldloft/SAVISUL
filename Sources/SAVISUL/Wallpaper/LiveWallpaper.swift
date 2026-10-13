import AppKit
import SpriteKit
import SwiftUI
import UniformTypeIdentifiers

/// Where the live wallpaper plays: behind SAVISUL's own panel, on the Mac's desktop, or both.
enum WallpaperTarget: String, CaseIterable, Identifiable {
    case off, app, desktop, both

    var id: String { rawValue }
    var inApp: Bool { self == .app || self == .both }
    var onDesktop: Bool { self == .desktop || self == .both }

    var copy: Copy {
        switch self {
        case .off: .wpOff
        case .app: .wpApp
        case .desktop: .wpDesktop
        case .both: .wpBoth
        }
    }
}

/// The live wallpaper's settings and the desktop windows that show it.
@MainActor @Observable
final class LiveWallpaper {
    static let shared = LiveWallpaper()

    private(set) var target: WallpaperTarget
    private(set) var landscape: WallpaperLandscape
    private(set) var customPath: String
    private(set) var glow: Bool
    @ObservationIgnored private let desktop = DesktopWallpaper()
    private var defaults: UserDefaults { SettingsDefaults.store }

    private init() {
        let defaults = SettingsDefaults.store
        target = WallpaperTarget(rawValue: defaults.string(forKey: "wallpaperTarget") ?? "") ?? .app
        let custom = defaults.string(forKey: "wallpaperCustom") ?? ""
        let path = FileManager.default.fileExists(atPath: custom) ? custom : ""
        customPath = path
        let scene = WallpaperLandscape(rawValue: defaults.string(forKey: "wallpaperScene") ?? "") ?? .bonsai
        landscape = scene == .custom && path.isEmpty ? .bonsai : scene
        glow = defaults.object(forKey: "wallpaperGlow") as? Bool ?? true
    }

    func start() {
        sync()
    }

    func setLandscape(_ landscape: WallpaperLandscape) {
        self.landscape = landscape
        defaults.set(landscape.rawValue, forKey: "wallpaperScene")
        sync()
    }

    /// Picks a picture, keeps a copy in SAVISUL's own folder, and makes it the wallpaper.
    func chooseCustomImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let source = panel.url else { return }
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SAVISUL/Wallpapers", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let ext = source.pathExtension.isEmpty ? "jpg" : source.pathExtension
        let copy = folder.appendingPathComponent("custom-\(UUID().uuidString.prefix(8)).\(ext)")
        guard (try? FileManager.default.copyItem(at: source, to: copy)) != nil, NSImage(contentsOf: copy) != nil else { return }
        if !customPath.isEmpty, customPath != copy.path { try? FileManager.default.removeItem(atPath: customPath) }
        customPath = copy.path
        defaults.set(customPath, forKey: "wallpaperCustom")
        setLandscape(.custom)
    }

    private func sync() {
        desktop.update(visible: target.onDesktop, landscape: landscape, custom: customPath, glow: glow)
    }

    func setTarget(_ target: WallpaperTarget) {
        self.target = target
        defaults.set(target.rawValue, forKey: "wallpaperTarget")
        sync()
    }

    func setGlow(_ glow: Bool) {
        self.glow = glow
        defaults.set(glow, forKey: "wallpaperGlow")
        sync()
    }
}

/// One borderless window per screen, just above the desktop picture and below the desktop's icons. It never takes
/// clicks, so the desktop behaves exactly as before; quitting SAVISUL brings the usual wallpaper back.
@MainActor
private final class DesktopWallpaper {
    private var windows: [NSWindow] = []
    private var observers: [NSObjectProtocol] = []
    private var glow = true
    private var landscape = WallpaperLandscape.bonsai
    private var custom = ""

    func update(visible: Bool, landscape: WallpaperLandscape, custom: String, glow: Bool) {
        self.glow = glow
        self.landscape = landscape
        self.custom = custom
        if visible {
            if windows.isEmpty { build() }
            if observers.isEmpty { observe() }
            for window in windows {
                guard let sakura = (window.contentView as? WallpaperView)?.sakura else { continue }
                sakura.glowEnabled = glow
                sakura.customPath = custom
                sakura.landscape = landscape
            }
        } else {
            tearDown()
        }
    }

    private func build() {
        for screen in NSScreen.screens {
            let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) - 1)
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            window.ignoresMouseEvents = true
            window.isOpaque = true
            window.hasShadow = false
            window.backgroundColor = SakuraArt.ground
            window.isReleasedWhenClosed = false
            window.setFrame(screen.frame, display: false)
            let view = WallpaperView(frame: CGRect(origin: .zero, size: screen.frame.size))
            let scene = SakuraScene(size: screen.frame.size, placement: .desktop, landscape: landscape)
            scene.customPath = custom
            scene.glowEnabled = glow
            view.presentScene(scene)
            window.contentView = view
            window.orderFront(nil)
            windows.append(window)
        }
    }

    private func tearDown() {
        for window in windows {
            (window.contentView as? SKView)?.presentScene(nil)
            window.orderOut(nil)
        }
        windows.removeAll()
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observers.removeAll()
    }

    private func observe() {
        // Screens come and go: rebuild so every display gets a window of its own size.
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                                object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.windows.isEmpty else { return }
                for window in self.windows { window.orderOut(nil) }
                self.windows.removeAll()
                self.build()
            }
        })
        let workspace = NSWorkspace.shared.notificationCenter
        for (name, paused) in [(NSWorkspace.screensDidSleepNotification, true), (NSWorkspace.screensDidWakeNotification, false),
                               (NSWorkspace.sessionDidResignActiveNotification, true), (NSWorkspace.sessionDidBecomeActiveNotification, false)] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    for window in self?.windows ?? [] { (window.contentView as? WallpaperView)?.asleep = paused }
                }
            })
        }
    }
}

/// The view a wallpaper scene plays in. It never answers clicks, and it stops drawing whenever it can't be seen —
/// behind a full-screen app, with the panel closed, or with the displays asleep.
final class WallpaperView: SKView {
    var sakura: SakuraScene? { scene as? SakuraScene }
    var asleep = false { didSet { refresh() } }
    private var occlusion: NSObjectProtocol?

    override init(frame: CGRect) {
        super.init(frame: frame)
        ignoresSiblingOrder = true
        allowsTransparency = false
        preferredFramesPerSecond = ProcessInfo.processInfo.isLowPowerModeEnabled ? 30 : 60
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // As smooth as the display allows: 120 frames a second on ProMotion screens, 30 in Low Power Mode.
        let display = window?.screen?.maximumFramesPerSecond ?? 60
        preferredFramesPerSecond = ProcessInfo.processInfo.isLowPowerModeEnabled ? 30 : min(max(display, 60), 120)
        if let occlusion { NotificationCenter.default.removeObserver(occlusion) }
        occlusion = nil
        guard let window else { return }
        occlusion = NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: window,
                                                           queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        refresh()
    }

    private func refresh() {
        let visible = window?.occlusionState.contains(.visible) ?? false
        isPaused = asleep || !visible
    }
}

/// The sakura behind SAVISUL's panel.
struct LiveWallpaperBackground: NSViewRepresentable {
    var landscape: WallpaperLandscape
    var customPath: String
    var glow: Bool

    func makeNSView(context: Context) -> WallpaperView {
        let view = WallpaperView(frame: CGRect(x: 0, y: 0, width: Metrics.panelWidth, height: Metrics.panelHeight))
        // An AppKit view isn't clipped by SwiftUI's clip shape, so it rounds its own corners to the panel's.
        view.wantsLayer = true
        view.layer?.cornerRadius = Metrics.panelRadius
        view.layer?.masksToBounds = true
        let scene = SakuraScene(size: CGSize(width: Metrics.panelWidth, height: Metrics.panelHeight), placement: .panel, landscape: landscape)
        scene.customPath = customPath
        scene.glowEnabled = glow
        view.presentScene(scene)
        return view
    }

    func updateNSView(_ view: WallpaperView, context: Context) {
        view.sakura?.glowEnabled = glow
        view.sakura?.customPath = customPath
        view.sakura?.landscape = landscape
    }
}

private struct WallpaperBehindKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True inside SAVISUL's panel while the live wallpaper plays behind it.
    var wallpaperBehind: Bool {
        get { self[WallpaperBehindKey.self] }
        set { self[WallpaperBehindKey.self] = newValue }
    }
}
