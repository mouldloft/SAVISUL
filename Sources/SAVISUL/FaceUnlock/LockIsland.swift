import AppKit
import Observation
import SwiftUI

/// Windows above the lock screen. macOS draws the lock screen in its own layer at level 300; a space at 400, where it puts
/// notifications over the lock screen, sits on top of it. Private API, looked up when first needed; when it is missing the
/// lock screen simply shows no island.
@MainActor
enum SkyLight {
    private typealias MainConnection = @convention(c) () -> Int32
    private typealias SpaceCreate = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias SpaceLevel = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias ShowSpaces = @convention(c) (Int32, CFArray) -> Int32
    private typealias MoveWindows = @convention(c) (Int32, Int32, CFArray, Int32) -> Int32

    private static let space: (connection: Int32, id: Int32, move: MoveWindows)? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight", RTLD_NOW),
              let main = dlsym(handle, "SLSMainConnectionID"), let create = dlsym(handle, "SLSSpaceCreate"),
              let level = dlsym(handle, "SLSSpaceSetAbsoluteLevel"), let show = dlsym(handle, "SLSShowSpaces"),
              let move = dlsym(handle, "SLSSpaceAddWindowsAndRemoveFromSpaces") else { return nil }
        let connection = unsafeBitCast(main, to: MainConnection.self)()
        let id = unsafeBitCast(create, to: SpaceCreate.self)(connection, 1, 0)
        guard id != 0 else { return nil }
        _ = unsafeBitCast(level, to: SpaceLevel.self)(connection, id, 400)
        _ = unsafeBitCast(show, to: ShowSpaces.self)(connection, [id] as CFArray)
        return (connection, id, unsafeBitCast(move, to: MoveWindows.self))
    }()

    /// Moves a window into the space above the lock screen.
    @discardableResult
    static func lift(_ window: NSWindow) -> Bool {
        guard let space else { return false }
        return space.move(space.connection, space.id, [window.windowNumber] as CFArray, 7) == 0
    }
}

/// The island at the lock screen, the way Face ID shows itself on iPhone: a padlock under the camera while the Mac is
/// locked, the face glyph while it looks, a checkmark when it knows you, a shake when it doesn't. It never takes a click
/// or a key, so the lock screen works exactly as without it.
@MainActor
@Observable
final class LockIsland {
    enum Phase: Equatable { case hidden, locked, scanning, recognized, failed, needsPassword }

    private(set) var phase: Phase = .hidden
    private(set) var shakes = 0
    private(set) var notch = CGSize(width: 185, height: 32)
    /// The face is known and only a blink is missing, so the island says so.
    private(set) var blinkHint = false

    @ObservationIgnored private var panel: NSPanel?
    @ObservationIgnored private var hiding: DispatchWorkItem?

    static let panelSize = NSSize(width: 340, height: 190)

    func show(_ next: Phase) {
        hiding?.cancel()
        hiding = nil
        let panel = panel ?? make()
        place(panel)
        if next == .failed { shakes += 1 }
        if !panel.isVisible {
            panel.orderFrontRegardless()
            let lifted = SkyLight.lift(panel)
            FaceLog.write("lock island shown; above the lock screen: \(lifted ? "yes" : "no")")
        }
        withAnimation(.islandSpring) {
            phase = next
            blinkHint = false
        }
    }

    func askForBlink() {
        guard phase == .scanning, !blinkHint else { return }
        withAnimation(.islandSpring) { blinkHint = true }
    }

    func hide() {
        guard phase != .hidden else { return }
        withAnimation(.islandSpring) { phase = .hidden }
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.phase == .hidden else { return }
                self.panel?.orderOut(nil)
            }
        }
        hiding = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    private func make() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: Self.panelSize), styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.hidesOnDeactivate = false
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.appearance = NSAppearance(named: .darkAqua)
        let hosting = NSHostingView(rootView: LockIslandView(island: self))
        hosting.frame = NSRect(origin: .zero, size: Self.panelSize)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
        self.panel = panel
        return panel
    }

    /// Centered on the notch of the built-in display, or on the top of the main one.
    private func place(_ panel: NSPanel) {
        let screen = ScreenSpace.notchScreen ?? NSScreen.main ?? NSScreen.screens[0]
        var center = screen.frame.midX
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea, screen.safeAreaInsets.top > 0 {
            notch = CGSize(width: max(right.minX - left.maxX, 120), height: screen.safeAreaInsets.top)
            center = (left.maxX + right.minX) / 2
        } else {
            notch = CGSize(width: 150, height: max(screen.frame.maxY - screen.visibleFrame.maxY, 24))
        }
        panel.setFrame(NSRect(x: (center - Self.panelSize.width / 2).rounded(), y: screen.frame.maxY - Self.panelSize.height,
                              width: Self.panelSize.width, height: Self.panelSize.height), display: false)
    }
}

struct LockIslandView: View {
    let island: LockIsland

    var body: some View {
        let size = shapeSize
        ZStack(alignment: .top) {
            NotchShape(top: 7, bottom: island.phase == .scanning || island.phase == .recognized ? 30 : 16)
                .fill(Color.black)
                .frame(width: size.width, height: size.height)
            content
                .padding(.top, island.notch.height + 6)
                .frame(width: size.width, height: size.height, alignment: .top)
                .opacity(island.phase == .hidden ? 0 : 1)
        }
        .frame(width: LockIsland.panelSize.width, height: LockIsland.panelSize.height, alignment: .top)
    }

    private var shapeSize: CGSize {
        let notch = island.notch
        switch island.phase {
        case .hidden: return notch
        case .locked, .failed: return CGSize(width: notch.width + 14, height: notch.height + 34)
        case .needsPassword: return CGSize(width: notch.width + 70, height: notch.height + 34)
        case .scanning, .recognized:
            return CGSize(width: max(notch.width + 24, 204), height: notch.height + 104 + (island.blinkHint ? 18 : 0))
        }
    }

    @ViewBuilder private var content: some View {
        switch island.phase {
        case .hidden:
            EmptyView()
        case .locked, .failed:
            Image(systemName: "lock.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(island.phase == .failed ? Palette.danger : Color.white)
                .modifier(Shake(times: CGFloat(island.shakes)))
                .animation(.easeInOut(duration: 0.45), value: island.shakes)
        case .needsPassword:
            Label(FacePhrases.enterPasswordHint.text, systemImage: "lock.fill")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Color.white)
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
        case .scanning, .recognized:
            let recognized = island.phase == .recognized
            VStack(spacing: 8) {
                ZStack {
                    ScanTicks(done: recognized)
                    Image(systemName: recognized ? "checkmark" : "faceid")
                        .font(.system(size: recognized ? 30 : 38, weight: recognized ? .bold : .light))
                        .foregroundStyle(recognized ? Palette.positive : Color.white)
                        .contentTransition(.symbolEffect(.replace))
                        .scaleEffect(recognized ? 1.08 : 1)
                }
                .frame(width: 80, height: 80)
                if island.blinkHint && !recognized {
                    Text(FacePhrases.blink.text)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.75))
                        .transition(.opacity)
                }
            }
            .padding(.top, 6)
        }
    }
}

/// The ring around the face glyph: a bright tick sweeps around with a fading tail while the camera looks,
/// and every tick turns green when it knows the face.
private struct ScanTicks: View {
    let done: Bool
    private static let count = 30

    var body: some View {
        TimelineView(.animation(paused: done)) { context in
            let turn = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.2) / 1.2
            ZStack {
                ForEach(0..<Self.count, id: \.self) { index in
                    let place = Double(index) / Double(Self.count)
                    let behind = (turn - place + 1).truncatingRemainder(dividingBy: 1)
                    Capsule()
                        .fill(done ? Palette.positive : Color.white.opacity(max(0.14, 1 - behind * 2.2)))
                        .frame(width: 2.6, height: 9)
                        .offset(y: -35)
                        .rotationEffect(.degrees(place * 360))
                }
            }
        }
        .animation(.easeOut(duration: 0.25), value: done)
    }
}

/// A short side-to-side shake, the way a passcode field says no.
private struct Shake: GeometryEffect {
    var times: CGFloat
    var animatableData: CGFloat {
        get { times }
        set { times = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 7 * sin(times * .pi * 4), y: 0))
    }
}
