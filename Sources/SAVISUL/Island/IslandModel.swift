import AppKit
import Observation
import SwiftUI

enum IslandTab: String, CaseIterable, Identifiable {
    case home, call, agents, files, camera

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .home: "house.fill"
        case .call: "phone.fill"
        case .agents: "sparkles"
        case .files: "tray.full.fill"
        case .camera: "web.camera.fill"
        }
    }

    var title: Phrase {
        switch self {
        case .home: Phrase("Home", ru: "Главное", uk: "Головне", fr: "Accueil")
        case .call: Phrase("Call", ru: "Звонок", uk: "Дзвінок", fr: "Appel")
        case .agents: Phrase("Agents", ru: "Агенты", uk: "Агенти", fr: "Agents")
        case .files: Phrase("Files", ru: "Файлы", uk: "Файли", fr: "Fichiers")
        case .camera: Phrase("Camera", ru: "Камера", uk: "Камера", fr: "Caméra")
        }
    }
}

/// A short message that drops out of the notch and goes back in.
struct IslandNotice: Identifiable {
    enum Style { case info, success, warning, alert }

    var id = UUID()
    var symbol: String
    var tint: Color
    var title: String
    var detail: String?
    var image: NSImage?
    var style: Style = .info
    var level: Double?
    var duration: Double = 3.4
    var actionTitle: String?
    var action: (@MainActor () -> Void)?
}

/// A level that changes in place while it moves, like the volume, and goes away a moment after.
struct IslandHUD: Equatable {
    var symbol: String
    var title: String
    var level: Double
    var muted: Bool
}

@MainActor
@Observable
final class IslandModel {
    enum Mode: Equatable { case collapsed, peek, expanded }

    var mode: Mode = .collapsed
    var tab: IslandTab = .home
    private(set) var notice: IslandNotice?
    /// A live activity that just started, shown under the notch for a few seconds.
    private(set) var livePeek: UUID?
    private(set) var hud: IslandHUD?
    var dropTargeted = false
    var dragNearby = false
    var notch = CGSize(width: 185, height: 32)
    var hasNotch = true
    var pinned = false
    /// Keeps the island open while something in it has the keyboard, like the agent task composer.
    var holding = false

    @ObservationIgnored private var queue: [IslandNotice] = []
    @ObservationIgnored private var noticeTask: DispatchWorkItem?
    @ObservationIgnored private var liveTask: DispatchWorkItem?
    @ObservationIgnored private var hudTask: DispatchWorkItem?
    @ObservationIgnored var onModeChange: (() -> Void)?
    /// Set by the controller: makes the island window take, or give back, the keyboard.
    @ObservationIgnored var onTakeKey: (() -> Void)?
    @ObservationIgnored var onReleaseKey: (() -> Void)?

    static let expandedWidth: CGFloat = 640
    static let wing: CGFloat = 46

    var contentHeight: CGFloat {
        switch tab {
        case .home: 186
        case .call: 150
        case .agents: Suite.shared.launcher.composing ? 184 : IslandAgents.height
        case .files: 190
        case .camera: 206
        }
    }
    static let peekWidth: CGFloat = 400
    static let peekContent: CGFloat = 54

    func post(_ notice: IslandNotice) {
        if let current = self.notice, current.title == notice.title, current.detail == notice.detail { return }
        if self.notice != nil, notice.level == nil {
            queue.append(notice)
            if queue.count > 3 { queue.removeFirst() }
            return
        }
        show(notice)
    }

    private func show(_ notice: IslandNotice) {
        noticeTask?.cancel()
        withAnimation(.islandSpring) {
            self.notice = notice
            if mode == .collapsed { mode = .peek }
        }
        onModeChange?()
        let task = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.dismissNotice() } }
        noticeTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + notice.duration, execute: task)
    }

    func dismissNotice() {
        noticeTask?.cancel()
        if !queue.isEmpty {
            show(queue.removeFirst())
            return
        }
        withAnimation(.islandSpring) {
            notice = nil
            if mode == .peek && livePeek == nil && hud == nil { mode = .collapsed }
        }
        onModeChange?()
    }

    /// Shows a level under the notch. While it keeps changing it updates in place instead of dropping in again.
    func show(hud: IslandHUD) {
        guard mode != .expanded else { return }
        hudTask?.cancel()
        if self.hud == nil {
            withAnimation(.islandSpring) {
                self.hud = hud
                if mode == .collapsed { mode = .peek }
            }
            onModeChange?()
        } else if self.hud != hud {
            withAnimation(.islandQuick) { self.hud = hud }
        }
        let task = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.endHUD() } }
        hudTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: task)
    }

    func endHUD() {
        hudTask?.cancel()
        guard hud != nil else { return }
        withAnimation(.islandSpring) {
            hud = nil
            if mode == .peek && notice == nil && livePeek == nil { mode = .collapsed }
        }
        onModeChange?()
    }

    /// Drops a starting activity out of the notch; it folds back into the wings after a moment.
    func peek(live id: UUID, for seconds: Double = 3.2) {
        guard Suite.shared.settings.islandNotices else { return }
        liveTask?.cancel()
        withAnimation(.islandSpring) {
            livePeek = id
            if mode == .collapsed { mode = .peek }
        }
        onModeChange?()
        let task = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.endPeek(live: id) } }
        liveTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: task)
    }

    func endPeek(live id: UUID) {
        guard livePeek == id else { return }
        liveTask?.cancel()
        withAnimation(.islandSpring) {
            livePeek = nil
            if mode == .peek && notice == nil && hud == nil { mode = .collapsed }
        }
        onModeChange?()
    }

    func expand(_ tab: IslandTab? = nil) {
        withAnimation(.islandSpring) {
            if let tab { self.tab = tab }
            mode = .expanded
        }
        onModeChange?()
    }

    /// Starts holding the island open and gives it the keyboard.
    func hold() {
        holding = true
        onTakeKey?()
    }

    /// Stops holding; the island closes as usual once the pointer is away.
    func release() {
        guard holding else { return }
        holding = false
        onReleaseKey?()
        onModeChange?()
    }

    func collapse() {
        guard !pinned, !holding else { return }
        withAnimation(.islandSpring) {
            mode = notice != nil || livePeek != nil || hud != nil ? .peek : .collapsed
        }
        onModeChange?()
    }
}

extension Animation {
    static let islandSpring = Animation.spring(response: 0.42, dampingFraction: 0.78, blendDuration: 0.1)
    static let islandQuick = Animation.spring(response: 0.3, dampingFraction: 0.86)
}

/// The notch outline: square top that flares into the menu bar, rounded bottom.
struct NotchShape: Shape {
    var top: CGFloat
    var bottom: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(top, bottom) }
        set {
            top = newValue.first
            bottom = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let top = min(self.top, rect.width / 4)
        let bottom = min(self.bottom, (rect.width - top * 2) / 2, rect.height - top)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.minX + top, y: rect.minY + top), control: CGPoint(x: rect.minX + top, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + top, y: rect.maxY - bottom))
        path.addQuadCurve(to: CGPoint(x: rect.minX + top + bottom, y: rect.maxY), control: CGPoint(x: rect.minX + top, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - top - bottom, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - top, y: rect.maxY - bottom), control: CGPoint(x: rect.maxX - top, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - top, y: rect.minY + top))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.maxX - top, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
