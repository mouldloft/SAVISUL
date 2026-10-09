import CoreAudio
import SwiftUI

struct SoundPane: View {
    var model: AppModel
    @State private var outputsOpen = false
    @State private var inputsOpen = false

    var body: some View {
        VStack(spacing: 12) {
            OutputCard(model: model, expanded: $outputsOpen)
            MixerCard(model: model, suite: Suite.shared)
            InputCard(model: model, expanded: $inputsOpen)
            SoundTricksCard(model: model, suite: Suite.shared)
        }
    }
}

private struct OutputCard: View {
    var model: AppModel
    @Binding var expanded: Bool

    var body: some View {
        let audio = model.audio
        VStack(alignment: .leading, spacing: 14) {
            DeviceHeader(caption: model.text(.output), device: audio.currentOutput, fallback: model.text(.noDevices),
                         expanded: expanded) { expanded.toggle() }
            if expanded {
                DeviceList(devices: audio.outputs, selected: audio.defaultOutput) { id in
                    model.audio.select(id, scope: .output)
                    expanded = false
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            if let device = audio.currentOutput {
                if let volume = device.volume {
                    VolumeReadout(model: model, volume: volume, muted: device.muted ?? false) {
                        model.audio.setMuted(!(device.muted ?? false), device: device.id, scope: .output)
                    }
                    FineSlider(value: volume) { model.audio.setVolume($0, device: device.id, scope: .output) }
                    StepRow(model: model, device: device.id, scope: .output)
                } else {
                    Footnote(model.text(.noVolume))
                }
                if audio.hasBalance {
                    Hairline()
                    BalanceRow(model: model)
                }
            }
        }
        .card(padding: 18)
        .animation(.panelSpring, value: expanded)
    }
}

private struct InputCard: View {
    var model: AppModel
    @Binding var expanded: Bool

    var body: some View {
        let audio = model.audio
        VStack(alignment: .leading, spacing: 12) {
            DeviceHeader(caption: model.text(.input), device: audio.currentInput, fallback: model.text(.noDevices),
                         expanded: expanded) { expanded.toggle() }
            if expanded {
                DeviceList(devices: audio.inputs, selected: audio.defaultInput) { id in
                    model.audio.select(id, scope: .input)
                    expanded = false
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            if let device = audio.currentInput, let volume = device.volume {
                HStack(spacing: 12) {
                    FineSlider(value: volume, tint: Palette.positive) {
                        model.audio.setVolume($0, device: device.id, scope: .input)
                    }
                    Text(model.percent(volume * 100))
                        .font(.system(size: 12.5, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Palette.secondary)
                        .frame(width: 44, alignment: .trailing)
                    if let muted = device.muted {
                        GlassIconButton(symbol: muted ? "mic.slash.fill" : "mic.fill", size: 32, selected: muted,
                                        help: model.text(muted ? .unmute : .mute)) {
                            model.audio.setMuted(!muted, device: device.id, scope: .input)
                        }
                    }
                }
            }
        }
        .card(padding: 18)
        .animation(.panelSpring, value: expanded)
    }
}

private struct DeviceHeader: View {
    let caption: String
    let device: AudioEndpoint?
    let fallback: String
    let expanded: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 12) {
                RowIcon(symbol: device?.symbol ?? "speaker.slash", tint: Palette.accent, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(caption)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Palette.secondary)
                    Text(device?.name ?? fallback)
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Palette.secondary)
                    .rotationEffect(.degrees(expanded ? 180 : 0))
                    .frame(width: 28, height: 28)
                    .floatingGlass(Circle(), shadow: false)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct DeviceList: View {
    let devices: [AudioEndpoint]
    let selected: AudioDeviceID
    let choose: (AudioDeviceID) -> Void

    var body: some View {
        VStack(spacing: 2) {
            ForEach(devices) { device in
                DeviceRow(device: device, selected: device.id == selected) { choose(device.id) }
            }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.black.opacity(0.2)))
    }
}

private struct DeviceRow: View {
    let device: AudioEndpoint
    let selected: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: device.symbol)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(selected ? Palette.accent : Palette.secondary)
                    .frame(width: 22)
                Text(device.name)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Palette.accent)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(hover || selected ? 0.07 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

private struct VolumeReadout: View {
    var model: AppModel
    let volume: Double
    let muted: Bool
    let toggleMute: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(model.decimal(volume * 100, digits: 1))
                .font(.system(size: 36, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(muted ? Palette.tertiary : Palette.ink)
                .contentTransition(.numericText(value: volume))
                .animation(.snappy(duration: 0.2), value: volume)
            Text("%")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(Palette.secondary)
            Spacer()
            GlassIconButton(symbol: muted ? "speaker.slash.fill" : "speaker.wave.2.fill", size: 38, selected: muted,
                            help: model.text(muted ? .unmute : .mute), action: toggleMute)
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 12 }
        }
    }
}

private struct StepRow: View {
    var model: AppModel
    let device: AudioDeviceID
    let scope: AudioScope

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 0) {
                step("−1", -0.01)
                divider
                step("−\(model.decimal(0.1, digits: 1))", -0.001)
                divider
                step("+\(model.decimal(0.1, digits: 1))", 0.001)
                divider
                step("+1", 0.01)
            }
            .frame(height: 30)
            .floatingGlass(Capsule(), shadow: false)
            Footnote(model.text(.fineHint))
        }
    }

    private var divider: some View {
        Rectangle().fill(Color.white.opacity(0.1)).frame(width: 0.5, height: 14)
    }

    private func step(_ label: String, _ delta: Double) -> some View {
        Button { model.audio.nudge(device: device, scope: scope, by: delta) } label: {
            Text(label)
                .font(.system(size: 12.5, weight: .semibold).monospacedDigit())
                .foregroundStyle(Palette.ink)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
    }
}

private struct BalanceRow: View {
    var model: AppModel

    var body: some View {
        let balance = model.audio.balance
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(model.text(.balance))
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Palette.secondary)
                Spacer()
                Text(label(balance))
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Palette.ink)
                    .contentTransition(.numericText())
                if abs(balance - 0.5) > 0.001 {
                    Button { model.audio.setBalance(0.5) } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundStyle(Palette.secondary)
                            .frame(width: 22, height: 22)
                            .floatingGlass(Circle(), shadow: false)
                    }
                    .buttonStyle(PressableStyle())
                    .help(model.text(.centerWord))
                }
            }
            HStack(spacing: 10) {
                Text(model.text(.leftShort)).font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.tertiary)
                FineSlider(value: balance, detent: 0.5, tint: Palette.ink.opacity(0.75)) { model.audio.setBalance($0) }
                Text(model.text(.rightShort)).font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.tertiary)
            }
        }
    }

    private func label(_ balance: Double) -> String {
        let offset = (balance - 0.5) * 200
        if abs(offset) < 0.5 { return model.text(.centerWord) }
        let side = offset < 0 ? model.text(.leftShort) : model.text(.rightShort)
        return "\(side) \(model.integer(Int(abs(offset).rounded())))"
    }
}