import AppKit
import Carbon.HIToolbox
import Observation
import SwiftUI

@MainActor
@Observable
final class RadialState {
    var actions: [SuiteAction] = []
    var highlighted: Int?
    var shown = false
}

/// Hold ⌃⌥R (or the middle mouse button) and flick toward an action; release to run it.
/// A quick tap leaves the ring open for a click.
@MainActor
final class RadialMenu {
    private let state = RadialState()
    private var panel: NSPanel?
    private var center = NSPoint.zero
    private var openedAt = Date()
    private var monitors: [Any] = []
    private(set) var isOpen = false
    private var sticky = false
    static let size: CGFloat = 360
    static let radius: CGFloat = 118

    func press() {
        if isOpen {
            if sticky { close(run: true) }
            return
        }
        open(at: NSEvent.mouseLocation)
    }

    func release() {
        guard isOpen else { return }
        if state.highlighted != nil {
            close(run: true)
        } else if Date().timeIntervalSince(openedAt) < 0.35 {
            sticky = true
        } else {
            close(run: false)
        }
    }

    private func open(at point: NSPoint) {
        let actions = Array(Suite.shared.settings.favorites.compactMap(SuiteActions.action).prefix(8))
        guard !actions.isEmpty else { return }
        state.actions = actions
        state.highlighted = nil
        isOpen = true
        sticky = false
        openedAt = Date()
        let screen = NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) } ?? ScreenSpace.mouseScreen
        let half = Self.size / 2
        let bounds = screen.frame
        center = NSPoint(x: min(max(point.x, bounds.minX + half), bounds.maxX - half),
                         y: min(max(point.y, bounds.minY + half), bounds.maxY - half))
        let panel = self.panel ?? make()
        panel.setFrame(NSRect(x: center.x - half, y: center.y - half, width: Self.size, height: Self.size), display: false)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.72)) { state.shown = true }
        if Suite.shared.settings.islandHaptics { NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now) }
        watch()
    }

    func close(run: Bool) {
        guard isOpen else { return }
        isOpen = false
        sticky = false
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors = []
        let chosen = run ? state.highlighted.flatMap { state.actions.indices.contains($0) ? state.actions[$0] : nil } : nil
        withAnimation(.easeIn(duration: 0.12)) { state.shown = false }
        if let panel {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.13) {
                MainActor.assumeIsolated { if !Suite.shared.commands.radial.isOpen { panel.orderOut(nil) } }
            }
        }
        if let chosen {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { MainActor.assumeIsolated { chosen.run() } }
        }
    }

    private func watch() {
        let moves: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: moves.union([.leftMouseDown, .rightMouseDown, .keyDown]), handler: { event in
            let type = event.type
            let code = event.keyCode
            MainActor.assumeIsolated { Suite.shared.commands.radial.event(type, code: code) }
        }) { monitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: moves, handler: { event in
            MainActor.assumeIsolated { Suite.shared.commands.radial.track() }
            return event
        }) { monitors.append(local) }
    }

    private func event(_ type: NSEvent.EventType, code: UInt16) {
        switch type {
        case .keyDown:
            if Int(code) == kVK_Escape { close(run: false) }
        case .leftMouseDown, .rightMouseDown:
            if sticky { close(run: state.highlighted != nil) }
        default:
            track()
        }
    }

    private func track() {
        let mouse = NSEvent.mouseLocation
        let dx = Double(mouse.x - center.x)
        let dy = Double(mouse.y - center.y)
        guard hypot(dx, dy) > 36 else {
            if state.highlighted != nil { state.highlighted = nil }
            return
        }
        let count = Double(state.actions.count)
        var angle = atan2(dx, dy)
        if angle < 0 { angle += 2 * .pi }
        let sector = 2 * .pi / count
        let index = Int((angle + sector / 2).truncatingRemainder(dividingBy: 2 * .pi) / sector) % state.actions.count
        guard index != state.highlighted else { return }
        withAnimation(.spring(response: 0.2, dampingFraction: 0.75)) { state.highlighted = index }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    fileprivate func pick(_ index: Int) {
        state.highlighted = index
        close(run: true)
    }

    private func make() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: Self.size, height: Self.size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.popUpMenuWindow)) + 2)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.animationBehavior = .none
        panel.hidesOnDeactivate = false
        panel.contentView = Glass.clear(RadialView(state: state, pick: { index in Suite.shared.commands.radial.pick(index) }),
                                        size: NSSize(width: Self.size, height: Self.size))
        self.panel = panel
        return panel
    }
}

private struct RadialView: View {
    let state: RadialState
    let pick: (Int) -> Void

    var body: some View {
        let count = max(state.actions.count, 1)
        let sector = 360.0 / Double(count)
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .overlay(Circle().fill(Color.black.opacity(0.42)))
                .overlay(Circle().strokeBorder(LinearGradient(colors: [Color.white.opacity(0.35), Color.white.opacity(0.06)],
                                                              startPoint: .top, endPoint: .bottom), lineWidth: 1))
                .frame(width: RadialMenu.radius * 2 + 82, height: RadialMenu.radius * 2 + 82)
                .shadow(color: .black.opacity(0.45), radius: 24, y: 10)
            if let index = state.highlighted {
                Circle()
                    .trim(from: 0, to: 1 / Double(count))
                    .stroke(Palette.accent.opacity(0.85), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .frame(width: RadialMenu.radius * 2 + 64, height: RadialMenu.radius * 2 + 64)
                    .rotationEffect(.degrees(-90 - sector / 2 + Double(index) * sector))
                    .shadow(color: Palette.accent.opacity(0.6), radius: 8)
            }
            VStack(spacing: 4) {
                if let index = state.highlighted, state.actions.indices.contains(index) {
                    Image(systemName: state.actions[index].symbol).font(.system(size: 20, weight: .semibold)).foregroundStyle(state.actions[index].tint)
                    Text(SuiteActions.title(state.actions[index])).font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.ink)
                        .multilineTextAlignment(.center).lineLimit(2)
                } else {
                    Image(systemName: "circle.grid.cross").font(.system(size: 18, weight: .semibold)).foregroundStyle(Palette.tertiary)
                }
            }
            .frame(width: 112, height: 112)
            .background(Circle().fill(Color.white.opacity(0.06)))
            ForEach(Array(state.actions.enumerated()), id: \.element.id) { index, action in
                let angle = Double(index) * sector * .pi / 180
                let selected = state.highlighted == index
                Button { pick(index) } label: {
                    Image(systemName: action.symbol)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(selected ? Palette.onLight : action.tint)
                        .frame(width: 56, height: 56)
                        .background(Circle().fill(selected ? Palette.accent : Color.white.opacity(0.1)))
                        .overlay(Circle().strokeBorder(Color.white.opacity(selected ? 0.5 : 0.14), lineWidth: 0.8))
                }
                .buttonStyle(PressableStyle())
                .scaleEffect(selected ? 1.16 : 1)
                .offset(x: sin(angle) * RadialMenu.radius, y: -cos(angle) * RadialMenu.radius)
                .help(SuiteActions.title(action))
            }
        }
        .frame(width: RadialMenu.size, height: RadialMenu.size)
        .scaleEffect(state.shown ? 1 : 0.6)
        .opacity(state.shown ? 1 : 0)
        .environment(\.colorScheme, .dark)
    }
}
