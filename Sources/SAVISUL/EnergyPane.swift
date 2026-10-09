import SwiftUI

struct EnergyPane: View {
    var model: AppModel

    var body: some View {
        VStack(spacing: 12) {
            LidCard(model: model)
            PowerFacts(model: model)
        }
    }
}

private struct LidCard: View {
    var model: AppModel

    var body: some View {
        let power = model.power
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                LidGlyph(awake: power.lidAwake)
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.text(.lidTitle))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        Text(state(at: context.date))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(power.lidAwake ? Palette.accent : Palette.secondary)
                            .contentTransition(.opacity)
                    }
                }
                Spacer(minLength: 8)
                GlassSwitch(isOn: power.lidAwake, busy: power.busy) { model.toggleLid() }
                    .accessibilityLabel(model.text(.lidTitle))
            }
            Text(model.text(power.lidAwake ? .lidExplainOn : .lidExplainOff))
                .font(.system(size: 12.5))
                .foregroundStyle(Palette.secondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            if power.confirmBattery {
                BatteryConfirm(model: model)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            if let message = power.message {
                InlineNotice(symbol: "exclamationmark.triangle.fill", text: text(for: message))
                    .transition(.opacity)
            }
            if power.restoredTimers {
                InlineNotice(symbol: "checkmark.circle.fill", text: model.text(.restoredTimers), tint: Palette.positive)
                    .transition(.opacity)
            }
        }
        .card(padding: 18)
        .animation(.panelSpring, value: power.confirmBattery)
        .animation(.panelSpring, value: power.lidAwake)
        .animation(.panelSpring, value: power.message)
    }

    private func state(at date: Date) -> String {
        let power = model.power
        if power.busy { return model.text(.lidWaiting) }
        guard power.lidAwake else { return model.text(.lidOff) }
        if let since = power.awakeSince, date.timeIntervalSince(since) >= 60 {
            return model.format(.lidOnFor, model.duration(date.timeIntervalSince(since)))
        }
        return model.text(.lidOn)
    }

    private func text(for message: PowerMessage) -> String {
        switch message {
        case .cancelled: model.text(.errCancelled)
        case .failed(let detail): model.format(.errFailed, detail)
        case .unverified: model.text(.errVerify)
        }
    }
}

private struct LidGlyph: View {
    let awake: Bool

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(systemName: "laptopcomputer")
                .font(.system(size: 21, weight: .medium))
                .foregroundStyle(awake ? Palette.accent : Palette.ink.opacity(0.8))
                .frame(width: 50, height: 50)
                .background(Circle().fill(awake ? Palette.accent.opacity(0.16) : Color.white.opacity(0.06)))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.6))
            Image(systemName: awake ? "bolt.fill" : "moon.fill")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(awake ? Palette.onLight : Palette.ink)
                .frame(width: 19, height: 19)
                .background(Circle().fill(awake ? Palette.accent : Color(white: 0.28)))
                .overlay(Circle().strokeBorder(Color.black.opacity(0.35), lineWidth: 1.5))
                .offset(x: 2, y: 2)
        }
        .symbolEffect(.bounce, value: awake)
        .accessibilityHidden(true)
    }
}

private struct BatteryConfirm: View {
    var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "battery.50percent")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.warning)
                Text(model.text(.batteryConfirmTitle))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.ink)
            }
            Text(model.text(.batteryConfirmBody))
                .font(.system(size: 12))
                .foregroundStyle(Palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Spacer()
                PillButton(title: model.text(.cancel)) { model.power.cancelConfirm() }
                PillButton(title: model.text(.turnOn), prominent: true) { model.confirmLidOnBattery() }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Palette.warning.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Palette.warning.opacity(0.22), lineWidth: 0.6))
    }
}

private struct PowerFacts: View {
    var model: AppModel

    var body: some View {
        let power = model.power
        VStack(spacing: 0) {
            ValueRow(symbol: batterySymbol, tint: Palette.positive, title: sourceTitle, value: powerSummary)
            Hairline(inset: 42)
            ValueRow(symbol: "moon", title: model.text(.rowIdleSleep), value: sleepSummary)
            if !power.sleepHolders.isEmpty {
                Hairline(inset: 42)
                ValueRow(symbol: "cup.and.saucer", tint: Palette.warning, title: model.text(.rowHeldBy),
                         value: power.sleepHolders.joined(separator: ", "))
            }
            Hairline(inset: 42)
            ToggleRow(symbol: "sun.max", tint: Palette.accent, title: model.text(.idleTitle), detail: model.text(.idleDetail),
                      isOn: power.idleHeld) {
                model.power.setIdle(!model.power.idleHeld)
            }
            Hairline(inset: 42)
            Button { model.run(.displayOff) } label: {
                HStack(spacing: 12) {
                    RowIcon(symbol: "moon.zzz")
                    Text(model.text(.menuDisplayOff))
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(Palette.ink)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Palette.tertiary)
                }
                .padding(.vertical, 7)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
        }
        .card(padding: 14)
    }

    private var batterySymbol: String {
        let battery = model.power.battery
        guard battery.present else { return "powerplug" }
        if battery.charging { return "battery.100percent.bolt" }
        switch battery.percent {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    private var sourceTitle: String {
        let battery = model.power.battery
        guard battery.present else { return model.text(.rowPower) }
        if battery.charging { return model.text(.srcCharging) }
        return model.text(battery.onAdapter ? .srcAdapter : .srcBattery)
    }

    private var powerSummary: String {
        let battery = model.power.battery
        guard battery.present else { return model.text(.srcAdapter) }
        let percent = model.percent(battery.percent)
        if battery.charging, let full = battery.minutesToFull {
            return "\(percent) · \(model.format(.timeToFull, model.duration(Double(full * 60))))"
        }
        if !battery.onAdapter, let left = battery.minutesToEmpty {
            return "\(percent) · \(model.format(.timeLeft, model.duration(Double(left * 60))))"
        }
        return percent
    }

    private var sleepSummary: String {
        if model.power.lidAwake { return model.text(.sleepNever) }
        guard let minutes = model.power.sleepMinutes else { return "—" }
        return minutes == 0 ? model.text(.sleepNever) : model.format(.sleepAfter, model.duration(Double(minutes * 60)))
    }
}
