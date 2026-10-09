import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class DockPreviewModel {
    var appName = ""
    var appPath: String?
    var entries: [WindowEntry] = []
    var thumbnails: [CGWindowID: NSImage] = [:]
    var tile = CGSize(width: 220, height: 150)
    var previews = true
    var horizontal = true
}

/// Window pictures above a Dock icon while the pointer rests on it. The Dock marks the icon
/// under the pointer as selected, so one Accessibility notification drives everything.
@MainActor
final class DockPreview {
    private struct Item {
        var pid: pid_t
        var url: URL?
        var frame: CGRect
    }

    private let model = DockPreviewModel()
    private var observer: AXObserver?
    private var observedDock: pid_t = 0
    private var list: AXUIElement?
    private var item: Item?
    private var panel: OverlayPanel?
    private var visible = false
    private var showWork: DispatchWorkItem?
    private var hideWork: DispatchWorkItem?
    private var monitors: [Any] = []
    private var watchdog: Timer?
    private var enabled = false
    private var loadTask: Task<Void, Never>?

    func enable(_ on: Bool) {
        guard on != enabled else { return }
        enabled = on
        if on {
            attach()
            watchdog = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
                MainActor.assumeIsolated { Suite.shared.windows.dock.attach() }
            }
        } else {
            watchdog?.invalidate()
            watchdog = nil
            detach()
            hide()
        }
    }

    /// Hooks the Dock's icon list; called again whenever the Dock restarts.
    fileprivate func attach() {
        guard enabled, AX.trusted,
              let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return }
        let pid = dock.processIdentifier
        guard pid != observedDock || observer == nil else { return }
        detach()
        let app = AX.app(pid)
        guard let list = AX.elements(app, kAXChildrenAttribute).first(where: { AX.role($0) == kAXListRole }) else { return }
        var created: AXObserver?
        guard AXObserverCreate(pid, { _, element, _, _ in
            MainActor.assumeIsolated { Suite.shared.windows.dock.selectionChanged(element) }
        }, &created) == .success, let created else { return }
        guard AXObserverAddNotification(created, list, kAXSelectedChildrenChangedNotification as CFString, nil) == .success else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)
        observer = created
        observedDock = pid
        self.list = list
    }

    private func detach() {
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        observer = nil
        list = nil
        observedDock = 0
    }

    fileprivate func selectionChanged(_ list: AXUIElement) {
        let selected = AX.elements(list, kAXSelectedChildrenAttribute).first
        guard let selected, AX.subrole(selected) == "AXApplicationDockItem", let frame = AX.frame(selected) else {
            item = nil
            showWork?.cancel()
            scheduleHide(0.32)
            return
        }
        let url = AX.value(selected, kAXURLAttribute) as? URL
        let running = url.flatMap { url in
            NSWorkspace.shared.runningApplications.first { $0.bundleURL?.standardizedFileURL == url.standardizedFileURL }
        }
        guard let running else {
            item = nil
            showWork?.cancel()
            scheduleHide(0.2)
            return
        }
        let next = Item(pid: running.processIdentifier, url: url, frame: frame)
        if item?.pid == next.pid, visible { return }
        item = next
        hideWork?.cancel()
        showWork?.cancel()
        let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.load(next, app: running) } }
        showWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (visible ? 0.06 : 0.38), execute: work)
    }

    private func load(_ item: Item, app: NSRunningApplication) {
        loadTask?.cancel()
        loadTask = Task { @MainActor [weak self] in
            let entries = await WindowCatalog.shared.entries(only: item.pid, includeEmptyApps: false)
            guard let self, self.item?.pid == item.pid else { return }
            guard !entries.isEmpty else {
                self.hide()
                return
            }
            self.model.appName = app.localizedName ?? ""
            self.model.appPath = app.bundleURL?.path
            self.model.entries = entries
            self.model.previews = WindowCatalog.shared.canCapture
            self.model.thumbnails = [:]
            for entry in entries { if let id = entry.windowID, let image = WindowCatalog.shared.cached(id) { self.model.thumbnails[id] = image } }
            self.present(item)
            guard self.model.previews else { return }
            let ids = entries.compactMap { $0.minimized ? nil : $0.windowID }
            let pictures = await WindowCatalog.shared.thumbnails(for: ids, fitting: CGSize(width: self.model.tile.width - 12, height: self.model.tile.height - 40), maxAge: 0.8)
            guard self.item?.pid == item.pid else { return }
            withAnimation(.easeOut(duration: 0.16)) { self.model.thumbnails.merge(pictures) { _, new in new } }
        }
    }

    private func present(_ item: Item) {
        let screen = ScreenSpace.screen(forAX: item.frame)
        let screenAX = ScreenSpace.toAX(screen.frame)
        let count = model.entries.count
        let bottom = abs(item.frame.maxY - screenAX.maxY) < 160
        let left = !bottom && item.frame.minX - screenAX.minX < 160
        model.horizontal = bottom
        var tile = model.previews ? CGSize(width: 236, height: 168) : CGSize(width: 200, height: 54)
        let spacing: CGFloat = 8
        let limit = (bottom ? screen.visibleFrame.width : screen.visibleFrame.height) * 0.92
        while CGFloat(count) * ((bottom ? tile.width : tile.height) + spacing) + 28 > limit && tile.width > 120 {
            tile = CGSize(width: tile.width * 0.88, height: tile.height * 0.88)
        }
        model.tile = CGSize(width: tile.width.rounded(), height: tile.height.rounded())
        let header: CGFloat = 30
        let size: NSSize
        if bottom {
            size = NSSize(width: CGFloat(count) * (model.tile.width + spacing) - spacing + 24, height: model.tile.height + header + 24)
        } else {
            size = NSSize(width: model.tile.width + 24, height: CGFloat(count) * (model.tile.height + spacing) - spacing + header + 24)
        }
        let anchor = ScreenSpace.toAppKit(item.frame)
        var origin: NSPoint
        if bottom {
            origin = NSPoint(x: anchor.midX - size.width / 2, y: anchor.maxY + 6)
        } else if left {
            origin = NSPoint(x: anchor.maxX + 6, y: anchor.midY - size.height / 2)
        } else {
            origin = NSPoint(x: anchor.minX - size.width - 6, y: anchor.midY - size.height / 2)
        }
        let bounds = screen.frame.insetBy(dx: 8, dy: 8)
        origin.x = min(max(origin.x, bounds.minX), bounds.maxX - size.width)
        origin.y = min(max(origin.y, bounds.minY), bounds.maxY - size.height)
        let frame = NSRect(origin: origin, size: size)
        let panel = self.panel ?? make()
        if visible {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            visible = true
            Glass.fadeIn(panel, to: frame, lift: bottom ? -8 : 0, key: false)
            watchMouse()
        }
    }

    private func make() -> OverlayPanel {
        let panel = OverlayPanel(size: NSSize(width: 300, height: 200), key: false, level: .popUpMenu)
        let view = DockPreviewView(model: model, pick: { [weak self] entry in
            self?.hide()
            Switcher.activate(entry)
        }, close: { [weak self] entry in
            guard let self, let element = entry.element else { return }
            AX.close(element)
            self.model.entries.removeAll { $0.id == entry.id }
            if self.model.entries.isEmpty { self.hide() } else if let item = self.item { self.present(item) }
        })
        panel.contentView = Glass.host(view, size: panel.frame.size, radius: 20)
        self.panel = panel
        return panel
    }

    private func watchMouse() {
        guard monitors.isEmpty else { return }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .rightMouseDown], handler: { event in
            let type = event.type
            MainActor.assumeIsolated { Suite.shared.windows.dock.pointer(type) }
        }) { monitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved], handler: { event in
            MainActor.assumeIsolated { Suite.shared.windows.dock.pointer(.mouseMoved) }
            return event
        }) { monitors.append(local) }
    }

    fileprivate func pointer(_ type: NSEvent.EventType) {
        guard visible, let panel else { return }
        let mouse = NSEvent.mouseLocation
        let inPanel = NSPointInRect(mouse, panel.frame.insetBy(dx: -8, dy: -8))
        if type == .leftMouseDown || type == .rightMouseDown {
            if !inPanel { hide() }
            return
        }
        if inPanel {
            hideWork?.cancel()
        } else if let item, NSPointInRect(mouse, ScreenSpace.toAppKit(item.frame).insetBy(dx: -4, dy: -4)) {
            hideWork?.cancel()
        } else {
            scheduleHide(0.3)
        }
    }

    private func scheduleHide(_ delay: TimeInterval) {
        guard visible else { return }
        if let panel, NSPointInRect(NSEvent.mouseLocation, panel.frame.insetBy(dx: -8, dy: -8)) { return }
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.hide() } }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func hide() {
        showWork?.cancel()
        hideWork?.cancel()
        loadTask?.cancel()
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors = []
        guard visible else { return }
        visible = false
        if let panel { Glass.fadeOut(panel, duration: 0.12) }
    }
}

private struct DockPreviewView: View {
    let model: DockPreviewModel
    let pick: (WindowEntry) -> Void
    let close: (WindowEntry) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                AppIconView(path: model.appPath, size: 18, fallback: "app")
                Text(model.appName).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Palette.ink).lineLimit(1)
                Text("\(model.entries.count)").font(.system(size: 11, weight: .semibold).monospacedDigit()).foregroundStyle(Palette.tertiary)
                Spacer(minLength: 0)
            }
            .frame(height: 22)
            let layout = model.horizontal ? AnyLayout(HStackLayout(spacing: 8)) : AnyLayout(VStackLayout(spacing: 8))
            layout {
                ForEach(model.entries) { entry in
                    DockTile(entry: entry, image: entry.windowID.flatMap { model.thumbnails[$0] }, previews: model.previews,
                             size: model.tile, pick: { pick(entry) }, close: { close(entry) })
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct DockTile: View {
    let entry: WindowEntry
    let image: NSImage?
    let previews: Bool
    let size: CGSize
    let pick: () -> Void
    let close: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: pick) {
            VStack(alignment: .leading, spacing: 6) {
                if previews {
                    ZStack {
                        RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.black.opacity(0.28))
                        if let image {
                            Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                                .padding(5)
                        } else {
                            AppIconView(path: entry.appPath, size: 40, fallback: "macwindow").opacity(0.7)
                        }
                    }
                    .frame(height: size.height - 34)
                }
                HStack(spacing: 5) {
                    if entry.minimized {
                        Image(systemName: "minus.circle.fill").font(.system(size: 9.5)).foregroundStyle(Palette.warning)
                    }
                    Text(entry.label).font(.system(size: 11.5, weight: .medium)).foregroundStyle(Palette.ink).lineLimit(1)
                    Spacer(minLength: 0)
                }
                .frame(height: 16)
            }
            .padding(6)
            .frame(width: size.width, height: size.height)
            .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Color.white.opacity(hover ? 0.12 : 0.04)))
            .overlay(alignment: .topTrailing) {
                if hover {
                    Button(action: close) {
                        Image(systemName: "xmark").font(.system(size: 8.5, weight: .bold)).foregroundStyle(Palette.ink)
                            .frame(width: 20, height: 20)
                            .background(Circle().fill(Color.black.opacity(0.55)))
                            .overlay(Circle().strokeBorder(Color.white.opacity(0.2), lineWidth: 0.6))
                    }
                    .buttonStyle(PressableStyle())
                    .padding(9)
                    .transition(.opacity)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in withAnimation(.easeOut(duration: 0.12)) { hover = inside } }
    }
}
