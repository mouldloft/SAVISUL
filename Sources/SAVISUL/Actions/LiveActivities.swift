import Observation
import SwiftUI

/// Something SAVISUL is busy with, shown around the notch while it runs: "Converting 17 images · 82%",
/// "Reading text · 12 of 18", "Asking AI". Any feature can start one; the island draws it.
@MainActor
@Observable
final class LiveActivity: Identifiable {
    enum State: Equatable { case running, done, failed }

    let id = UUID()
    let symbol: String
    let tint: Color
    private(set) var title: String
    private(set) var detail: String?
    /// 0…1, or nil while the amount of work is unknown.
    private(set) var progress: Double?
    private(set) var state: State = .running
    let started = Date()
    @ObservationIgnored weak var center: LiveActivityCenter?

    init(symbol: String, tint: Color, title: String, detail: String?) {
        self.symbol = symbol
        self.tint = tint
        self.title = title
        self.detail = detail
    }

    func update(progress: Double?, detail: String? = nil) {
        guard state == .running else { return }
        self.progress = progress.map { min(max($0, 0), 1) }
        if let detail { self.detail = detail }
    }

    /// Ends it. A message, when given, drops out of the notch as a short notice.
    func finish(_ message: String?) {
        guard state == .running else { return }
        state = .done
        progress = 1
        center?.ended(self, message: message, failed: false)
    }

    func fail(_ message: String) {
        guard state == .running else { return }
        state = .failed
        center?.ended(self, message: message, failed: true)
    }
}

@MainActor
@Observable
final class LiveActivityCenter {
    private(set) var items: [LiveActivity] = []

    /// The newest activity still running, the one the closed island shows.
    var current: LiveActivity? { items.last { $0.state == .running } }

    @discardableResult
    func start(symbol: String, tint: Color = Palette.accent, title: String, detail: String? = nil) -> LiveActivity {
        let activity = LiveActivity(symbol: symbol, tint: tint, title: title, detail: detail)
        activity.center = self
        withAnimation(.islandSpring) { items.append(activity) }
        Suite.shared.island.peek(live: activity.id)
        return activity
    }

    fileprivate func ended(_ activity: LiveActivity, message: String?, failed: Bool) {
        withAnimation(.islandSpring) { items.removeAll { $0.id == activity.id } }
        Suite.shared.island.endPeek(live: activity.id)
        guard let message, !message.isEmpty else { return }
        Suite.shared.notify(IslandNotice(symbol: failed ? "exclamationmark.triangle.fill" : "checkmark.circle.fill",
                                         tint: failed ? Palette.warning : Palette.positive, title: activity.title, detail: message,
                                         style: failed ? .warning : .success, duration: failed ? 4.5 : 2.6))
    }
}

/// A ring that fills with progress around the activity's symbol, or turns while the end is unknown.
struct LiveRing: View {
    let activity: LiveActivity
    var size: CGFloat = 20

    var body: some View {
        ZStack {
            Circle().stroke(activity.tint.opacity(0.22), lineWidth: 2.2)
            if let progress = activity.progress {
                Circle().trim(from: 0, to: max(progress, 0.03))
                    .stroke(activity.tint, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.islandQuick, value: progress)
            } else {
                Circle().trim(from: 0, to: 0.28)
                    .stroke(activity.tint, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                    .modifier(Spinning())
            }
            Image(systemName: activity.symbol).font(.system(size: size * 0.4, weight: .bold)).foregroundStyle(activity.tint)
        }
        .frame(width: size, height: size)
    }
}

/// The open notch's line for an activity: title, detail, a progress bar and the percentage or the time so far.
struct LiveRow: View {
    let activity: LiveActivity

    var body: some View {
        HStack(spacing: 12) {
            LiveRing(activity: activity, size: 30)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(activity.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.ink).lineLimit(1)
                    if let detail = activity.detail {
                        Text(detail).font(.system(size: 11.5)).foregroundStyle(Palette.secondary).lineLimit(1).truncationMode(.middle)
                    }
                }
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.12))
                        if let progress = activity.progress {
                            Capsule().fill(activity.tint).frame(width: max(5, proxy.size.width * progress))
                                .animation(.islandQuick, value: progress)
                        } else {
                            Capsule().fill(activity.tint.opacity(0.7)).frame(width: proxy.size.width * 0.3).modifier(Sweeping(width: proxy.size.width))
                        }
                    }
                }
                .frame(height: 4)
            }
            LiveValue(activity: activity)
                .frame(minWidth: 40, alignment: .trailing)
        }
        .padding(.horizontal, 18)
        .frame(height: IslandModel.peekContent)
    }
}

/// "82%" when the share is known, the running time otherwise.
struct LiveValue: View {
    let activity: LiveActivity

    var body: some View {
        if let progress = activity.progress {
            Text(Say.percent(progress * 100))
                .font(.system(size: 11.5, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(activity.tint)
        } else {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(Say.clock(context.date.timeIntervalSince(activity.started)))
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(activity.tint)
            }
        }
    }
}

/// A short highlight that slides along a bar while the end is unknown.
private struct Sweeping: ViewModifier {
    let width: CGFloat
    @State private var on = false

    func body(content: Content) -> some View {
        content
            .offset(x: on ? width * 0.7 : 0)
            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: on)
            .onAppear { on = true }
    }
}
