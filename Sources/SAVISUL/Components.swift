import AppKit
import SwiftUI

@MainActor
final class IconCache {
    static let shared = IconCache()
    private var images: [String: NSImage] = [:]

    func icon(bundleID: String) -> NSImage? {
        if let hit = images[bundleID] { return hit }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        images[bundleID] = image
        return image
    }

    func icon(path: String) -> NSImage {
        if let hit = images[path] { return hit }
        let image = NSWorkspace.shared.icon(forFile: path)
        images[path] = image
        return image
    }
}

struct AppIconView: View {
    var bundleID: String? = nil
    var path: String? = nil
    var size: CGFloat = 28
    var fallback = "app.dashed"

    var body: some View {
        if let image = resolved {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
        } else {
            RowIcon(symbol: fallback, size: size)
        }
    }

    private var resolved: NSImage? {
        if let path, FileManager.default.fileExists(atPath: path) { return IconCache.shared.icon(path: path) }
        if let bundleID { return IconCache.shared.icon(bundleID: bundleID) }
        return nil
    }
}

struct RowIcon: View {
    let symbol: String
    var tint: Color = Palette.ink
    var size: CGFloat = 30

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
        Image(systemName: symbol)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(shape.fill(tint.opacity(0.15)))
            .overlay(shape.strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5))
            .accessibilityHidden(true)
    }
}

struct Hairline: View {
    var inset: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(Palette.hairline)
            .frame(height: 0.5)
            .padding(.leading, inset)
    }
}

struct CardTitle<Trailing: View>: View {
    let text: String
    let trailing: Trailing

    init(_ text: String, @ViewBuilder trailing: () -> Trailing) {
        self.text = text
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(text)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.ink)
            Spacer(minLength: 8)
            trailing
        }
    }
}

extension CardTitle where Trailing == EmptyView {
    init(_ text: String) {
        self.init(text) { EmptyView() }
    }
}

struct Footnote: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 11.5))
            .foregroundStyle(Palette.tertiary)
            .lineSpacing(1.5)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ValueRow: View {
    let symbol: String
    var tint: Color = Palette.ink
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            RowIcon(symbol: symbol, tint: tint)
            Text(title)
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(Palette.ink)
            Spacer(minLength: 10)
            Text(value)
                .font(.system(size: 12.5))
                .foregroundStyle(Palette.secondary)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .contentTransition(.opacity)
        }
        .padding(.vertical, 7)
        .accessibilityElement(children: .combine)
    }
}

struct ToggleRow: View {
    let symbol: String
    var tint: Color = Palette.ink
    let title: String
    var detail: String? = nil
    let isOn: Bool
    var busy = false
    let action: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            RowIcon(symbol: symbol, tint: tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(Palette.ink)
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 10)
            GlassSwitch(isOn: isOn, busy: busy, action: action)
                .accessibilityLabel(title)
        }
        .padding(.vertical, 7)
    }
}

struct InlineNotice: View {
    let symbol: String
    let text: String
    var tint: Color = Palette.warning

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 11.5, weight: .bold))
                .foregroundStyle(tint)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(Palette.ink.opacity(0.88))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(tint.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(tint.opacity(0.22), lineWidth: 0.6))
    }
}

struct CalloutAction {
    let title: String
    var prominent = false
    let run: () -> Void
}

/// Explains why a permission is needed and offers the one next step that works in its current state.
struct PermissionCallout: View {
    let symbol: String
    let title: String
    let message: String
    let actions: [CalloutAction]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                RowIcon(symbol: symbol, tint: Palette.warning)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                ForEach(Array(actions.enumerated()), id: \.offset) { _, action in
                    PillButton(title: action.title, prominent: action.prominent, action: action.run)
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Palette.warning.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Palette.warning.opacity(0.22), lineWidth: 0.6))
    }
}

struct LevelBar: View {
    let fraction: Double
    var tint: Color = Palette.accent
    var height: CGFloat = 5

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08))
                Capsule()
                    .fill(LinearGradient(colors: [tint.opacity(0.65), tint], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(height, geo.size.width * CGFloat(min(max(fraction, 0), 1))))
            }
        }
        .frame(height: height)
        .animation(.panelSpring, value: fraction)
    }
}

struct Sparkline: View {
    let values: [Double]
    var slots = 60
    var tint: Color = Palette.accent

    var body: some View {
        Canvas { context, size in
            var floor = Path()
            floor.move(to: CGPoint(x: 0, y: size.height - 0.5))
            floor.addLine(to: CGPoint(x: size.width, y: size.height - 0.5))
            context.stroke(floor, with: .color(.white.opacity(0.1)), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
            guard values.count > 1 else { return }
            let step = size.width / CGFloat(max(slots - 1, 1))
            let start = size.width - CGFloat(values.count - 1) * step
            var line = Path()
            for (index, value) in values.enumerated() {
                let point = CGPoint(x: start + CGFloat(index) * step,
                                    y: size.height - 1 - CGFloat(min(max(value, 0), 100) / 100) * (size.height - 2))
                if index == 0 { line.move(to: point) } else { line.addLine(to: point) }
            }
            var area = line
            area.addLine(to: CGPoint(x: size.width, y: size.height))
            area.addLine(to: CGPoint(x: start, y: size.height))
            area.closeSubpath()
            context.fill(area, with: .linearGradient(Gradient(colors: [tint.opacity(0.32), tint.opacity(0)]),
                                                     startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            context.stroke(line, with: .color(tint), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
        .frame(height: 30)
        .accessibilityHidden(true)
    }
}

struct GlassField: View {
    let prompt: String
    @Binding var text: String
    var monospaced = false

    var body: some View {
        TextField(prompt, text: $text)
            .textFieldStyle(.plain)
            .font(monospaced ? .system(size: 12.5, design: .monospaced) : .system(size: 13))
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.black.opacity(0.28)))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Color.white.opacity(0.12), lineWidth: 0.6))
    }
}

/// Code an agent wrote: lines added and removed, and new files. Symbols keep it free of plural rules.
struct CodeLine: View {
    let code: CodeTally
    var size: CGFloat = 11

    var body: some View {
        HStack(spacing: 6) {
            if code.added > 0 || code.removed > 0 {
                Text("+" + Say.compact(code.added)).foregroundStyle(Palette.positive)
                Text("−" + Say.compact(code.removed)).foregroundStyle(Palette.danger.opacity(0.9))
            }
            if code.filesCreated > 0 {
                Label(Say.number(code.filesCreated), systemImage: "doc.badge.plus").foregroundStyle(Palette.accent)
            }
            if code.filesEdited > 0 {
                Label(Say.number(code.filesEdited), systemImage: "pencil.line").foregroundStyle(Palette.secondary)
            }
        }
        .font(.system(size: size, weight: .semibold).monospacedDigit())
        .labelStyle(CompactLabel())
        .lineLimit(1)
        .help(CodeLine.help(code))
    }

    @MainActor static func help(_ code: CodeTally) -> String {
        Phrase("%@ lines added, %@ removed · %@ new files · %@ files edited",
               ru: "%@ строк добавлено, %@ удалено · новых файлов: %@ · изменено файлов: %@",
               uk: "%@ рядків додано, %@ видалено · нових файлів: %@ · змінено файлів: %@",
               fr: "%@ lignes ajoutées, %@ supprimées · %@ nouveaux fichiers · %@ fichiers modifiés")(
            Say.number(code.added), Say.number(code.removed), Say.number(code.filesCreated), Say.number(code.filesEdited))
    }
}

struct CompactLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 2) {
            configuration.icon.imageScale(.small)
            configuration.title
        }
    }
}
