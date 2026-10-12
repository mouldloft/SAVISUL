import AppKit
import SpriteKit
import SwiftUI

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
    private(set) var glow: Bool
    @ObservationIgnored private let desktop = DesktopWallpaper()
    private var defaults: UserDefaults { SettingsDefaults.store }

    private init() {
        let defaults = SettingsDefaults.store
        target = WallpaperTarget(rawValue: defaults.string(forKey: "wallpaperTarget") ?? "") ?? .app
        landscape = WallpaperLandscape(rawValue: defaults.string(forKey: "wallpaperScene") ?? "") ?? .bonsai
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

    private func sync() {
        desktop.update(visible: target.onDesktop, landscape: landscape, glow: glow)
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

    func update(visible: Bool, landscape: WallpaperLandscape, glow: Bool) {
        self.glow = glow
        self.landscape = landscape
        if visible {
            if windows.isEmpty { build() }
            if observers.isEmpty { observe() }
            for window in windows {
                guard let sakura = (window.contentView as? WallpaperView)?.sakura else { continue }
                sakura.glowEnabled = glow
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
    var glow: Bool

    func makeNSView(context: Context) -> WallpaperView {
        let view = WallpaperView(frame: CGRect(x: 0, y: 0, width: Metrics.panelWidth, height: Metrics.panelHeight))
        // An AppKit view isn't clipped by SwiftUI's clip shape, so it rounds its own corners to the panel's.
        view.wantsLayer = true
        view.layer?.cornerRadius = Metrics.panelRadius
        view.layer?.masksToBounds = true
        let scene = SakuraScene(size: CGSize(width: Metrics.panelWidth, height: Metrics.panelHeight), placement: .panel, landscape: landscape)
        scene.glowEnabled = glow
        view.presentScene(scene)
        return view
    }

    func updateNSView(_ view: WallpaperView, context: Context) {
        view.sakura?.glowEnabled = glow
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
