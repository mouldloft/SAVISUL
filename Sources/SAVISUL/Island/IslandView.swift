import AppKit
import SwiftUI

/// What the closed island shows on either side of the camera.
enum IslandActivity: Hashable {
    case none
    case ringing(UUID)
    case call
    case live(UUID)
    case media
    case agent(AgentKind)
    case timer(UUID)
    case download
    case recording
    case micMuted

    @MainActor static func current(_ suite: Suite) -> IslandActivity {
        let s = suite.settings
        if s.islandTimers, let ringing = suite.timers.timers.first(where: \.ringing) { return .ringing(ringing.id) }
        if s.islandCalls, suite.calls.current != nil { return .call }
        if suite.app?.capture.isRecording == true { return .recording }
        if let live = suite.live.current { return .live(live.id) }
        if s.islandMusic, suite.nowPlaying.playing { return .media }
        if s.islandAgents, let agent = suite.agents.working.first { return .agent(agent.kind) }
        if s.islandTimers, let timer = suite.timers.nearest, timer.running || timer.pausedRemaining != nil { return .timer(timer.id) }
        if s.islandDownloads, !suite.downloads.active.isEmpty { return .download }
        if suite.micMuted { return .micMuted }
        return .none
    }

    /// During a call the island opens on the call and its controls; otherwise on the tab last used.
    @MainActor static func openingTab(_ suite: Suite) -> IslandTab? {
        suite.settings.islandCalls && suite.calls.current != nil ? .call : nil
    }

    /// An agent at work while the island already shows something else, music or a call: it gets a bubble of its own.
    @MainActor static func companion(_ suite: Suite, beside primary: IslandActivity) -> AgentKind? {
        guard suite.settings.islandAgents, primary != .none else { return nil }
        if case .agent = primary { return nil }
        return suite.agents.working.first?.kind
    }
}

enum IslandLayout {
    @MainActor static func size(for model: IslandModel, activity: IslandActivity) -> CGSize {
        let notch = model.notch
        switch model.mode {
        case .collapsed:
            if activity == .none {
                return model.hasNotch ? CGSize(width: notch.width, height: notch.height) : CGSize(width: 0, height: 0)
            }
            return CGSize(width: notch.width + IslandModel.wing * 2 + ear(.collapsed) * 2, height: notch.height)
        case .peek:
            return CGSize(width: max(IslandModel.peekWidth, notch.width + IslandModel.wing * 2) + ear(.peek) * 2,
                          height: notch.height + IslandModel.peekContent)
        case .expanded:
            return CGSize(width: IslandModel.expandedWidth + ear(.expanded) * 2, height: notch.height + model.contentHeight)
        }
    }

    static func ear(_ mode: IslandModel.Mode) -> CGFloat {
        switch mode {
        case .collapsed: 6
        case .peek: 10
        case .expanded: 14
        }
    }

    static func radius(_ mode: IslandModel.Mode) -> CGFloat {
        switch mode {
        case .collapsed: 10
        case .peek: 22
        case .expanded: 30
        }
    }
}

struct IslandRoot: View {
    let suite: Suite
    let model: IslandModel

    static let bubbleGap: CGFloat = 7

    var body: some View {
        let activity = IslandActivity.current(suite)
        let companion = model.mode == .collapsed ? IslandActivity.companion(suite, beside: activity) : nil
        let size = IslandLayout.size(for: model, activity: activity)
        let idle = model.mode == .collapsed && activity == .none
        let ear = idle ? 0 : IslandLayout.ear(model.mode)
        let radius = idle ? 8 : IslandLayout.radius(model.mode)
        let shape = NotchShape(top: ear, bottom: radius)
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                if activity == .call && model.mode != .expanded {
                    shape.stroke(Palette.positive.opacity(0.75), lineWidth: 1.5)
                        .blur(radius: 5)
                        .modifier(Breathing())
                        .transition(.opacity)
                }
                shape.fill(Color.black)
                content(activity)
                    .padding(.horizontal, ear)
                    .frame(width: size.width, height: size.height, alignment: .top)
                    .clipShape(shape)
                if model.dropTargeted {
                    shape.stroke(Palette.accent.opacity(0.9), lineWidth: 1.5)
                }
            }
            .frame(width: size.width, height: size.height)
            .overlay(alignment: .topTrailing) {
                if let companion {
                    CompanionBubble(kind: companion, height: model.notch.height)
                        .offset(x: CompanionBubble.width(model.notch.height) + Self.bubbleGap)
                        .transition(.scale(scale: 0.2, anchor: .leading).combined(with: .opacity))
                }
            }
            .shadow(color: .black.opacity(model.mode == .collapsed ? 0 : 0.55), radius: model.mode == .expanded ? 26 : 14, y: 10)
            .contentShape(shape)
            .onTapGesture {
                if model.mode != .expanded { model.expand(IslandActivity.openingTab(suite)) }
            }
            .onDrop(of: [.fileURL, .url, .image, .plainText], isTargeted: Binding(get: { model.dropTargeted }, set: { model.dropTargeted = $0 })) { providers in
                guard suite.settings.islandShelf else { return false }
                model.tab = .files
                return suite.shelf.accept(providers)
            }
            Spacer(minLength: 0)
        }
        .frame(width: IslandController.panelSize.width, height: IslandController.panelSize.height, alignment: .top)
        .animation(.islandSpring, value: model.mode)
        .animation(.islandSpring, value: activity)
        .animation(.islandSpring, value: companion)
        .environment(\.locale, suite.language.locale)
    }

    @ViewBuilder
    private func content(_ activity: IslandActivity) -> some View {
        switch model.mode {
        case .collapsed:
            if activity != .none {
                WingsRow(suite: suite, activity: activity, notch: model.notch)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        case .peek:
            VStack(spacing: 0) {
                WingsRow(suite: suite, activity: activity, notch: model.notch)
                    .frame(height: model.notch.height)
                if let hud = model.hud {
                    HUDRow(hud: hud)
                        .id("hud")
                        .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: -10)), removal: .opacity))
                } else if let notice = model.notice {
                    NoticeRow(notice: notice) { model.dismissNotice() }
                        .id(notice.id)
                        .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: -10)), removal: .opacity))
                } else if let id = model.livePeek, let live = suite.live.items.first(where: { $0.id == id }) {
                    LiveRow(activity: live)
                        .id(id)
                        .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: -10)), removal: .opacity))
                }
            }
        case .expanded:
            ExpandedIsland(suite: suite, model: model)
                .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .top)))
        }
    }
}

// MARK: Closed island

private struct WingsRow: View {
    let suite: Suite
    let activity: IslandActivity
    let notch: CGSize

    var body: some View {
        HStack(spacing: 0) {
            left.frame(width: IslandModel.wing, height: notch.height)
                .id(activity)
                .transition(.blurReplace)
            Spacer(minLength: notch.width)
            right.frame(width: IslandModel.wing, height: notch.height)
                .id(activity)
                .transition(.blurReplace)
        }
        .padding(.horizontal, 2)
    }

    @ViewBuilder private var left: some View {
        switch activity {
        case .call:
            CallBadge(call: suite.calls.current, size: 20)
        case .media:
            Artwork(image: suite.nowPlaying.artwork, size: 22, radius: 6)
        case .agent(let kind):
            AgentGlyph(kind: kind, size: 20, working: true)
        case .live(let id):
            if let live = suite.live.items.first(where: { $0.id == id }) { LiveRing(activity: live, size: 20) }
        case .timer, .ringing:
            Image(systemName: "timer").font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.accent)
                .symbolEffect(.pulse, isActive: isRinging)
        case .download:
            DownloadRing(progress: suite.downloads.active.first?.progress, size: 20)
        case .recording:
            Circle().fill(Palette.danger).frame(width: 9, height: 9).modifier(Breathing())
        case .micMuted:
            Image(systemName: "mic.slash.fill").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.danger)
        case .none:
            EmptyView()
        }
    }

    @ViewBuilder private var right: some View {
        switch activity {
        case .call:
            if suite.callMicOff {
                Image(systemName: "mic.slash.fill").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Palette.danger)
            } else if let call = suite.calls.current {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(Say.clock(context.date.timeIntervalSince(call.since)))
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(Palette.positive)
                }
            }
        case .media:
            EqualizerBars(playing: suite.nowPlaying.playing, tint: suite.nowPlaying.tint, levels: suite.spectrumLevels, count: 4, height: 13)
        case .agent(let kind):
            let status = suite.agents.status(kind)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(Say.clock(context.date.timeIntervalSince(status.since ?? context.date)))
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(kind.tint)
            }
        case .live(let id):
            if let live = suite.live.items.first(where: { $0.id == id }) { LiveValue(activity: live) }
        case .timer(let id), .ringing(let id):
            if let timer = suite.timers.timers.first(where: { $0.id == id }) {
                TimelineView(.periodic(from: .now, by: 0.5)) { context in
                    Text(timer.ringing ? "0:00" : Say.clock(timer.remaining(at: context.date).rounded(.up)))
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(timer.ringing ? Palette.danger : Palette.ink)
                        .opacity(timer.pausedRemaining != nil ? 0.55 : 1)
                }
            }
        case .download:
            if let progress = suite.downloads.active.first?.progress {
                Text(Say.percent(progress * 100)).font(.system(size: 11.5, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Palette.ink)
            } else {
                Image(systemName: "arrow.down").font(.system(size: 12, weight: .bold)).foregroundStyle(Palette.positive)
                    .symbolEffect(.pulse)
            }
        case .recording:
            if let start = suite.app?.capture.recordingStart {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(Say.clock(context.date.timeIntervalSince(start)))
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(Palette.danger)
                }
            }
        case .micMuted, .none:
            EmptyView()
        }
    }

    private var isRinging: Bool {
        if case .ringing = activity { return true }
        return false
    }
}

/// The app on the call, in a mint ring that breathes while the call lasts.
private struct CallBadge: View {
    let call: CallMonitor.Call?
    var size: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(Palette.positive.opacity(0.16))
            Circle().stroke(Palette.positive.opacity(0.9), lineWidth: 1.4).modifier(Breathing())
            if let path = call?.appPath {
                Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable().aspectRatio(contentMode: .fit)
                    .frame(width: size * 0.74, height: size * 0.74)
            } else {
                Image(systemName: "phone.fill").font(.system(size: size * 0.45, weight: .bold)).foregroundStyle(Palette.positive)
            }
        }
        .frame(width: size, height: size)
    }
}

/// A second activity in a small island of its own, split off to the right, the way iPhone shows two at once.
struct CompanionBubble: View {
    let kind: AgentKind
    let height: CGFloat

    static func width(_ height: CGFloat) -> CGFloat { height + IslandLayout.ear(.collapsed) * 2 }

    var body: some View {
        let ear = IslandLayout.ear(.collapsed)
        ZStack(alignment: .top) {
            NotchShape(top: ear, bottom: IslandLayout.radius(.collapsed)).fill(Color.black)
            AgentGlyph(kind: kind, size: height * 0.62, working: true)
                .frame(height: height)
        }
        .frame(width: Self.width(height), height: height)
    }
}

/// The volume while it moves: device, level and percent, changing in place.
private struct HUDRow: View {
    let hud: IslandHUD

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.white.opacity(hud.muted ? 0.07 : 0.12)).frame(width: 32, height: 32)
                Image(systemName: hud.symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(hud.muted ? Palette.danger : Palette.ink)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Text(hud.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.ink).lineLimit(1)
                    Spacer(minLength: 8)
                    Text(hud.muted ? "—" : Say.percent(hud.level * 100))
                        .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(Palette.secondary)
                        .contentTransition(.numericText(value: hud.level))
                }
                LevelPill(value: hud.muted ? 0 : hud.level, tint: hud.muted ? Palette.tertiary : Palette.ink)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: IslandModel.peekContent)
    }
}

private struct NoticeRow: View {
    let notice: IslandNotice
    let dismiss: () -> Void
    @State private var shown = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                if let image = notice.image {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fit).frame(width: 30, height: 30)
                        .scaleEffect(shown ? 1 : 0.55)
                        .animation(.spring(response: 0.38, dampingFraction: 0.58), value: shown)
                } else {
                    Circle().fill(notice.tint.opacity(0.18)).frame(width: 32, height: 32)
                    Image(systemName: notice.symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(notice.tint)
                        .symbolEffect(.bounce, value: shown)
                }
            }
            .frame(width: 34, height: 34)
            .onAppear { shown = true }
            VStack(alignment: .leading, spacing: 2) {
                Text(notice.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.ink).lineLimit(1)
                if let detail = notice.detail {
                    Text(detail).font(.system(size: 11.5)).foregroundStyle(Palette.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if let level = notice.level {
                LevelPill(value: level, tint: notice.tint).frame(width: 110)
            } else if let title = notice.actionTitle, let action = notice.action {
                Button {
                    action()
                    dismiss()
                } label: {
                    Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.onLight)
                        .padding(.horizontal, 12).frame(height: 26)
                        .background(Capsule().fill(notice.tint))
                }
                .buttonStyle(PressableStyle())
            }
        }
        .padding(.horizontal, 16)
        .frame(height: IslandModel.peekContent)
        .contentShape(Rectangle())
        .onTapGesture(perform: dismiss)
    }
}

private struct LevelPill: View {
    let value: Double
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12))
                Capsule().fill(tint).frame(width: max(6, proxy.size.width * min(max(value, 0), 1)))
            }
        }
        .frame(height: 6)
        .animation(.islandQuick, value: value)
    }
}

// MARK: Open island

private struct ExpandedIsland: View {
    let suite: Suite
    let model: IslandModel

    var body: some View {
        VStack(spacing: 0) {
            header.frame(height: model.notch.height)
            Group {
                switch model.tab {
                case .home: IslandHome(suite: suite)
                case .call:
                    if let call = suite.calls.current { IslandCall(suite: suite, call: call) } else { IslandHome(suite: suite) }
                case .agents: IslandAgents(suite: suite)
                case .files: IslandFiles(suite: suite, model: model)
                case .camera: IslandCamera(suite: suite)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .transition(.opacity)
            .id(model.tab)
        }
    }

    private var header: some View {
        HStack(spacing: 0) {
            HStack(spacing: 4) {
                ForEach(tabs) { tab in
                    TabChip(tab: tab, selected: model.tab == tab) {
                        withAnimation(.islandQuick) { model.tab = tab }
                    }
                }
            }
            .padding(.leading, 12)
            Spacer(minLength: model.notch.width + 16)
            HStack(spacing: 8) {
                StatusCluster(suite: suite)
                HeaderButton(symbol: model.pinned ? "pin.fill" : "pin", active: model.pinned) { model.pinned.toggle() }
                HeaderButton(symbol: "gearshape.fill", active: false) {
                    model.pinned = false
                    model.collapse()
                    suite.openSettings()
                }
            }
            .padding(.trailing, 12)
        }
        .padding(.top, 2)
    }

    private var tabs: [IslandTab] {
        IslandTab.allCases.filter { tab in
            switch tab {
            case .home: true
            case .call: suite.settings.islandCalls && suite.calls.current != nil
            case .agents: suite.settings.islandAgents
            case .files: suite.settings.islandShelf || suite.settings.islandDownloads
            case .camera: suite.settings.islandCamera
            }
        }
    }
}

private struct TabChip: View {
    let tab: IslandTab
    let selected: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: tab.symbol).font(.system(size: 11, weight: .semibold))
                if selected { Text(tab.title.text).font(.system(size: 11.5, weight: .semibold)).lineLimit(1) }
            }
            .foregroundStyle(selected ? Palette.onLight : (hover ? Palette.ink : Palette.secondary))
            .padding(.horizontal, selected ? 10 : 8)
            .frame(height: 22)
            .background(Capsule().fill(selected ? Palette.accent : Color.white.opacity(hover ? 0.1 : 0.0)))
        }
        .buttonStyle(PressableStyle())
        .onHover { hover = $0 }
    }
}

private struct HeaderButton: View {
    let symbol: String
    let active: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(active ? Palette.accent : (hover ? Palette.ink : Palette.tertiary))
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.white.opacity(hover ? 0.1 : 0)))
        }
        .buttonStyle(PressableStyle())
        .onHover { hover = $0 }
    }
}

/// Battery and the current output device, the two facts people glance at most.
private struct StatusCluster: View {
    let suite: Suite

    var body: some View {
        HStack(spacing: 8) {
            if let audio = suite.app?.audio.currentOutput {
                Image(systemName: audio.muted == true ? "speaker.slash.fill" : audio.symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.secondary)
                    .help(audio.name)
            }
            if let battery = suite.app?.power.battery, battery.present {
                HStack(spacing: 3) {
                    Text(Say.percent(battery.percent)).font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                    Image(systemName: battery.charging ? "battery.100percent.bolt" : Self.batterySymbol(battery.percent))
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(battery.percent <= 20 && !battery.charging ? Palette.danger : (battery.charging ? Palette.positive : Palette.secondary))
                }
                .foregroundStyle(Palette.secondary)
            }
        }
    }

    static func batterySymbol(_ percent: Double) -> String {
        switch percent {
        case ..<13: "battery.0percent"
        case ..<38: "battery.25percent"
        case ..<63: "battery.50percent"
        case ..<88: "battery.75percent"
        default: "battery.100percent"
        }
    }
}

// MARK: Pieces shared by the island tabs

struct Artwork: View {
    let image: NSImage?
    var size: CGFloat
    var radius: CGFloat

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                LinearGradient(colors: [Color.white.opacity(0.14), Color.white.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "music.note").font(.system(size: size * 0.42, weight: .semibold)).foregroundStyle(Palette.tertiary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

/// Bars that follow real levels when the mixer can hear the Mac, and breathe on their own otherwise.
struct EqualizerBars: View {
    let playing: Bool
    let tint: Color
    let levels: [Float]
    var count: Int
    var height: CGFloat

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !playing)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: max(2, height * 0.16)) {
                ForEach(0..<count, id: \.self) { index in
                    Capsule()
                        .fill(LinearGradient(colors: [tint, tint.opacity(0.7)], startPoint: .top, endPoint: .bottom))
                        .frame(width: max(2.5, height * 0.22), height: max(3, height * level(index, time)))
                }
            }
            .frame(height: height)
        }
    }

    private func level(_ index: Int, _ time: Double) -> CGFloat {
        guard playing else { return 0.22 }
        if !levels.isEmpty {
            let position = Double(index) / Double(max(count - 1, 1)) * Double(levels.count - 1)
            let value = CGFloat(levels[min(Int(position.rounded()), levels.count - 1)])
            return min(max(value, 0.14), 1)
        }
        let seed = Double(index) * 1.7
        let wave = sin(time * (5.2 + seed) + seed) * 0.5 + sin(time * (8.3 - seed * 0.6) + seed * 2) * 0.3
        return CGFloat(0.5 + wave * 0.45).clamped(0.16, 1)
    }
}

struct DownloadRing: View {
    let progress: Double?
    var size: CGFloat

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.16), lineWidth: 2.2)
            if let progress {
                Circle().trim(from: 0, to: progress).stroke(Palette.positive, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            } else {
                Circle().trim(from: 0, to: 0.28).stroke(Palette.positive, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                    .modifier(Spinning())
            }
            Image(systemName: "arrow.down").font(.system(size: size * 0.42, weight: .bold)).foregroundStyle(Palette.positive)
        }
        .frame(width: size, height: size)
        .animation(.islandQuick, value: progress)
    }
}

struct AgentGlyph: View {
    let kind: AgentKind
    var size: CGFloat
    var working: Bool

    var body: some View {
        ZStack {
            Circle().fill(kind.tint.opacity(0.16))
            if working {
                Circle().trim(from: 0, to: 0.3)
                    .stroke(AngularGradient(colors: [kind.tint.opacity(0), kind.tint], center: .center), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                    .modifier(Spinning())
            }
            Image(systemName: kind.symbol).font(.system(size: size * 0.46, weight: .bold)).foregroundStyle(kind.tint)
        }
        .frame(width: size, height: size)
    }
}

struct Spinning: ViewModifier {
    @State private var angle = 0.0

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(angle))
            .onAppear {
                withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) { angle = 360 }
            }
    }
}

struct Breathing: ViewModifier {
    @State private var on = false

    func body(content: Content) -> some View {
        content
            .opacity(on ? 1 : 0.35)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { on = true }
            }
    }
}

extension Comparable {
    func clamped(_ low: Self, _ high: Self) -> Self { min(max(self, low), high) }
}
