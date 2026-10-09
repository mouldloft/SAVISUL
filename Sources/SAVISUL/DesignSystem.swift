import AppKit
import SwiftUI

enum Palette {
    static let ink = Color(red: 0.97, green: 0.96, blue: 0.94)
    static let secondary = Color.white.opacity(0.64)
    static let tertiary = Color.white.opacity(0.48)
    static let hairline = Color.white.opacity(0.09)
    static let accent = Color(red: 0.86, green: 0.78, blue: 0.64)
    static let accentDeep = Color(red: 0.69, green: 0.59, blue: 0.44)
    static let positive = Color(red: 0.55, green: 0.84, blue: 0.69)
    static let warning = Color(red: 0.96, green: 0.73, blue: 0.40)
    static let danger = Color(red: 1.0, green: 0.45, blue: 0.39)
    static let onLight = Color(red: 0.08, green: 0.08, blue: 0.09)
}

enum Metrics {
    static let panelWidth: CGFloat = 400
    static let panelHeight: CGFloat = 656
    static let panelRadius: CGFloat = 26
    static let cardRadius: CGFloat = 20
    static let gutter: CGFloat = 14
}

extension Animation {
    static let panelSpring = Animation.spring(response: 0.34, dampingFraction: 0.86)
    static let quickSpring = Animation.spring(response: 0.24, dampingFraction: 0.8)
}

// MARK: Surfaces

struct CardSurface: ViewModifier {
    var radius: CGFloat
    var padding: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
                ZStack {
                    shape.fill(Color.white.opacity(0.055))
                    shape.fill(LinearGradient(
                        colors: [Color.white.opacity(0.06), Color.white.opacity(0)],
                        startPoint: .top, endPoint: .center))
                    shape.strokeBorder(LinearGradient(
                        colors: [Color.white.opacity(0.2), Color.white.opacity(0.05), Color.white.opacity(0.09)],
                        startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.8)
                }
            }
    }
}

struct FloatingGlass<S: InsettableShape>: ViewModifier {
    var shape: S
    var shadow: Bool
    var strength: Double

    func body(content: Content) -> some View {
        content.background {
            ZStack {
                shape.fill(.ultraThinMaterial)
                shape.fill(Color.white.opacity(0.06 * strength))
                shape.fill(LinearGradient(
                    colors: [Color.white.opacity(0.14 * strength), Color.white.opacity(0)],
                    startPoint: .top, endPoint: .bottom))
                shape.strokeBorder(LinearGradient(
                    colors: [Color.white.opacity(0.42), Color.white.opacity(0.07), Color.white.opacity(0.2)],
                    startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.8)
            }
            .compositingGroup()
            .shadow(color: Color.black.opacity(shadow ? 0.36 : 0), radius: 14, x: 0, y: 7)
        }
    }
}

extension View {
    func card(radius: CGFloat = Metrics.cardRadius, padding: CGFloat = 16) -> some View {
        modifier(CardSurface(radius: radius, padding: padding))
    }

    func floatingGlass<S: InsettableShape>(_ shape: S, shadow: Bool = true, strength: Double = 1) -> some View {
        modifier(FloatingGlass(shape: shape, shadow: shadow, strength: strength))
    }
}

// MARK: Controls

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.86 : 1)
            .animation(.quickSpring, value: configuration.isPressed)
    }
}

struct GlassIconButton: View {
    let symbol: String
    var size: CGFloat = 34
    var selected = false
    var tint: Color = Palette.ink
    let help: String
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(selected ? Palette.onLight : tint)
                .frame(width: size, height: size)
                .background {
                    Circle().fill(selected ? Palette.ink : Color.white.opacity(hover ? 0.09 : 0))
                }
                .floatingGlass(Circle(), shadow: false)
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .onHover { hover = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}

struct PillButton: View {
    let title: String
    var symbol: String? = nil
    var prominent = false
    var tint: Color = Palette.ink
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 11, weight: .bold))
                }
                Text(title).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
            }
            .foregroundStyle(prominent ? Palette.onLight : tint)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background {
                Capsule().fill(prominent ? Palette.ink : Color.white.opacity(hover ? 0.08 : 0))
            }
            .floatingGlass(Capsule(), shadow: false)
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .onHover { hover = $0 }
    }
}

struct Spinner: View {
    var size: CGFloat = 14
    var color: Color = Palette.ink

    var body: some View {
        TimelineView(.animation) { context in
            let turn = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 0.9) / 0.9
            Circle()
                .trim(from: 0.12, to: 0.82)
                .stroke(color, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                .rotationEffect(.degrees(turn * 360))
        }
        .frame(width: size, height: size)
    }
}

struct GlassSwitch: View {
    let isOn: Bool
    var busy = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn
                        ? AnyShapeStyle(LinearGradient(colors: [Palette.accent, Palette.accentDeep], startPoint: .top, endPoint: .bottom))
                        : AnyShapeStyle(Color.white.opacity(0.14)))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(isOn ? 0.3 : 0.12), lineWidth: 0.8))
                Circle()
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                    .padding(2.5)
                    .overlay {
                        if busy { Spinner(size: 11, color: Palette.onLight) }
                    }
            }
            .frame(width: 46, height: 28)
            .animation(.panelSpring, value: isOn)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .accessibilityValue(isOn ? "1" : "0")
    }
}

/// Drag anywhere on the track to jump there; hold Option for tenfold finer movement.
struct FineSlider: View {
    var value: Double
    var range: ClosedRange<Double> = 0...1
    var detent: Double? = nil
    var tint: Color = Palette.accent
    var onChange: (Double) -> Void
    var onEnd: (() -> Void)? = nil

    private struct Anchor {
        var x: CGFloat
        var value: Double
        var fine: Bool
    }

    @State private var dragging = false
    @State private var anchor: Anchor?

    private let knob: CGFloat = 20

    var body: some View {
        GeometryReader { geo in
            let track = max(geo.size.width - knob, 1)
            let position = CGFloat(normalized(value))
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.black.opacity(0.3))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5))
                    .frame(height: 6)
                Capsule()
                    .fill(LinearGradient(colors: [tint.opacity(0.7), tint], startPoint: .leading, endPoint: .trailing))
                    .frame(width: knob / 2 + track * position + 3, height: 6)
                if let detent {
                    Capsule()
                        .fill(Color.white.opacity(0.4))
                        .frame(width: 2, height: 11)
                        .offset(x: knob / 2 + track * CGFloat(normalized(detent)) - 1)
                }
                Circle()
                    .fill(Color.white)
                    .overlay(Circle().strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5))
                    .frame(width: knob, height: knob)
                    .shadow(color: .black.opacity(0.35), radius: dragging ? 6 : 3, y: dragging ? 3 : 1.5)
                    .scaleEffect(dragging ? 1.14 : 1)
                    .offset(x: track * position)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(drag(track: track))
        }
        .frame(height: 24)
        .animation(.quickSpring, value: dragging)
    }

    private func normalized(_ raw: Double) -> Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return min(max((raw - range.lowerBound) / span, 0), 1)
    }

    private func drag(track: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { gesture in
                let span = range.upperBound - range.lowerBound
                let fine = NSEvent.modifierFlags.contains(.option)
                if anchor == nil {
                    dragging = true
                    let start: Double
                    if fine {
                        start = value
                    } else {
                        let fraction = min(max((gesture.startLocation.x - knob / 2) / track, 0), 1)
                        start = range.lowerBound + Double(fraction) * span
                    }
                    anchor = Anchor(x: gesture.startLocation.x, value: start, fine: fine)
                }
                if let current = anchor, current.fine != fine {
                    anchor = Anchor(x: gesture.location.x, value: value, fine: fine)
                }
                guard let active = anchor else { return }
                let factor = active.fine ? 0.1 : 1.0
                var next = active.value + Double((gesture.location.x - active.x) / track) * span * factor
                next = min(max(next, range.lowerBound), range.upperBound)
                if let detent, abs(next - detent) < span * 0.018 {
                    if abs(value - detent) > span * 0.0001 {
                        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                    }
                    next = detent
                }
                onChange(next)
            }
            .onEnded { _ in
                dragging = false
                anchor = nil
                onEnd?()
            }
    }
}

struct SegmentItem<Value: Hashable>: Identifiable {
    let value: Value
    let title: String
    var id: Value { value }
}

struct GlassSegmented<Value: Hashable>: View {
    let items: [SegmentItem<Value>]
    let selection: Value
    let onSelect: (Value) -> Void
    @Namespace private var space

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items) { item in
                segment(item)
            }
        }
        .padding(3)
        .floatingGlass(Capsule(), shadow: false)
        .animation(.panelSpring, value: selection)
    }

    private func segment(_ item: SegmentItem<Value>) -> some View {
        let selected = item.value == selection
        return Button { onSelect(item.value) } label: {
            Text(item.title)
                .font(.system(size: 12, weight: selected ? .semibold : .medium))
                .foregroundStyle(selected ? Palette.onLight : Palette.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .frame(height: 26)
                .background {
                    if selected {
                        Capsule().fill(Palette.ink).matchedGeometryEffect(id: "selection", in: space)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: Feedback

struct Toast: Equatable, Identifiable {
    enum Tone { case info, success, warning, danger }

    let id = UUID()
    var symbol: String
    var text: String
    var tone: Tone = .info

    var color: Color {
        switch tone {
        case .info: Palette.ink
        case .success: Palette.positive
        case .warning: Palette.warning
        case .danger: Palette.danger
        }
    }
}

struct ToastView: View {
    let toast: Toast

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: toast.symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(toast.color)
            Text(toast.text)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Palette.ink)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .floatingGlass(Capsule(), strength: 1.3)
        .padding(.horizontal, 24)
    }
}
