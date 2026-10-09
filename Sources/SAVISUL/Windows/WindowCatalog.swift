import AppKit
@preconcurrency import ScreenCaptureKit

/// One window, or one app that has none, as the switcher and the Dock previews show it.
struct WindowEntry: Identifiable {
    let id: String
    let pid: pid_t
    let windowID: CGWindowID?
    let appName: String
    let appPath: String?
    let bundleID: String?
    var title: String
    var frame: CGRect?
    var minimized: Bool
    var hidden: Bool
    var order: Int
    let element: AXUIElement?

    var isWindow: Bool { element != nil }
    var label: String { title.isEmpty ? appName : title }
}

final class AXBox: @unchecked Sendable {
    let element: AXUIElement
    init(_ element: AXUIElement) { self.element = element }
}

@MainActor
final class WindowCatalog {
    static let shared = WindowCatalog()

    private var appOrder: [pid_t] = []
    private var cache: [CGWindowID: (image: NSImage, at: Date)] = [:]
    private var observer: NSObjectProtocol?

    func start() {
        guard observer == nil else { return }
        if let front = NSWorkspace.shared.frontmostApplication { appOrder = [front.processIdentifier] }
        observer = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                                                     object: nil, queue: .main) { note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            let pid = app.processIdentifier
            MainActor.assumeIsolated { WindowCatalog.shared.touch(pid) }
        }
    }

    private func touch(_ pid: pid_t) {
        guard pid != ProcessInfo.processInfo.processIdentifier else { return }
        appOrder.removeAll { $0 == pid }
        appOrder.insert(pid, at: 0)
        if appOrder.count > 80 { appOrder.removeLast() }
    }

    /// The app used just before the current one, for a quick ⌥Tab tap.
    var previousApp: NSRunningApplication? {
        let running = Set(RunningApps.regular().map(\.processIdentifier))
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        guard let pid = appOrder.first(where: { $0 != front && running.contains($0) }) else { return nil }
        return NSRunningApplication(processIdentifier: pid)
    }

    private struct Raw: @unchecked Sendable {
        var pid: pid_t
        var id: CGWindowID?
        var title: String
        var frame: CGRect?
        var minimized: Bool
        var box: AXBox
    }

    /// Windows front to back, then apps without windows. Accessibility is read off the main thread,
    /// in parallel, so one frozen app cannot stall the switcher.
    func entries(only pid: pid_t? = nil, includeEmptyApps: Bool = true) async -> [WindowEntry] {
        var apps = RunningApps.regular()
        if let pid { apps = apps.filter { $0.processIdentifier == pid } }
        let pids = apps.map(\.processIdentifier)
        let raw = await Task.detached(priority: .userInitiated) { Self.collect(pids) }.value
        let z = Self.zOrder()
        var result: [WindowEntry] = []
        for app in apps {
            let pid = app.processIdentifier
            let mru = appOrder.firstIndex(of: pid) ?? 60
            let name = app.localizedName ?? ""
            let path = app.bundleURL?.path
            let windows = raw[pid] ?? []
            for (index, window) in windows.enumerated() {
                let onScreen = window.id.flatMap { z[$0] }
                let order = onScreen ?? (window.minimized ? 20_000 : 10_000) + mru * 50 + index
                result.append(WindowEntry(id: window.id.map { "w\($0)" } ?? "p\(pid)-\(index)", pid: pid, windowID: window.id,
                                          appName: name, appPath: path, bundleID: app.bundleIdentifier, title: window.title,
                                          frame: window.frame, minimized: window.minimized, hidden: app.isHidden,
                                          order: app.isHidden ? 15_000 + mru * 50 + index : order, element: window.box.element))
            }
            if windows.isEmpty && includeEmptyApps {
                result.append(WindowEntry(id: "a\(pid)", pid: pid, windowID: nil, appName: name, appPath: path,
                                          bundleID: app.bundleIdentifier, title: "", frame: nil, minimized: false,
                                          hidden: app.isHidden, order: 30_000 + mru, element: nil))
            }
        }
        return result.sorted { $0.order < $1.order }
    }

    nonisolated private static func collect(_ pids: [pid_t]) -> [pid_t: [Raw]] {
        let lock = NSLock()
        var out: [pid_t: [Raw]] = [:]
        DispatchQueue.concurrentPerform(iterations: pids.count) { index in
            let pid = pids[index]
            var list: [Raw] = []
            for window in AX.windows(pid) where AX.isStandardWindow(window) {
                let frame = AX.frame(window)
                if let frame, frame.width < 40 || frame.height < 30 { continue }
                list.append(Raw(pid: pid, id: AX.windowID(window), title: AX.title(window) ?? "", frame: frame,
                                minimized: AX.bool(window, kAXMinimizedAttribute) ?? false, box: AXBox(window)))
            }
            lock.lock()
            out[pid] = list
            lock.unlock()
        }
        return out
    }

    /// Front-to-back position of every normal window on the current Space.
    nonisolated static func zOrder() -> [CGWindowID: Int] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return [:] }
        var order: [CGWindowID: Int] = [:]
        var index = 0
        for info in list where (info[kCGWindowLayer as String] as? Int ?? 0) == 0 {
            if let id = info[kCGWindowNumber as String] as? CGWindowID {
                order[id] = index
                index += 1
            }
        }
        return order
    }

    /// The topmost normal window under a point, read from the window server without Accessibility.
    nonisolated static func window(at point: CGPoint) -> (id: CGWindowID, pid: pid_t, frame: CGRect)? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
        for info in list {
            guard let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary), frame.contains(point) else { continue }
            guard (info[kCGWindowLayer as String] as? Int ?? 0) == 0 else { return nil }
            guard let id = info[kCGWindowNumber as String] as? CGWindowID,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t else { return nil }
            return (id, pid, frame)
        }
        return nil
    }

    var canCapture: Bool { CGPreflightScreenCaptureAccess() }

    func cached(_ id: CGWindowID) -> NSImage? { cache[id]?.image }

    /// Live pictures of windows through ScreenCaptureKit; recent ones come from the cache at once.
    func thumbnails(for ids: [CGWindowID], fitting box: CGSize, maxAge: TimeInterval = 1.5) async -> [CGWindowID: NSImage] {
        guard canCapture, !ids.isEmpty else { return [:] }
        let now = Date()
        var result: [CGWindowID: NSImage] = [:]
        var missing: [CGWindowID] = []
        for id in ids {
            if let hit = cache[id], now.timeIntervalSince(hit.at) < maxAge { result[id] = hit.image } else { missing.append(id) }
        }
        guard !missing.isEmpty else { return result }
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let fresh = await Task.detached(priority: .userInitiated) { await Self.capture(missing, box: box, scale: scale) }.value
        for (id, image) in fresh {
            let picture = NSImage(cgImage: image, size: NSSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale))
            cache[id] = (picture, Date())
            result[id] = picture
        }
        if cache.count > 160 {
            let stale = cache.filter { now.timeIntervalSince($0.value.at) > 60 }.map(\.key)
            stale.forEach { cache[$0] = nil }
        }
        return result
    }

    nonisolated private static func capture(_ ids: [CGWindowID], box: CGSize, scale: CGFloat) async -> [CGWindowID: CGImage] {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false) else { return [:] }
        var windows: [CGWindowID: SCWindow] = [:]
        for window in content.windows { windows[window.windowID] = window }
        return await withTaskGroup(of: (CGWindowID, CGImage?).self) { group in
            for id in ids {
                guard let window = windows[id] else { continue }
                group.addTask { (id, await shot(window, box: box, scale: scale)) }
            }
            var out: [CGWindowID: CGImage] = [:]
            for await (id, image) in group {
                if let image { out[id] = image }
            }
            return out
        }
    }

    nonisolated private static func shot(_ window: SCWindow, box: CGSize, scale: CGFloat) async -> CGImage? {
        let frame = window.frame
        guard frame.width > 2, frame.height > 2 else { return nil }
        let fit = min(box.width / frame.width, box.height / frame.height, 1) * scale
        let config = SCStreamConfiguration()
        config.width = max(Int(frame.width * fit), 2)
        config.height = max(Int(frame.height * fit), 2)
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = true
        config.scalesToFit = true
        let filter = SCContentFilter(desktopIndependentWindow: window)
        return try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }
}
