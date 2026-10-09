import SwiftUI

struct SystemPane: View {
    var model: AppModel

    var body: some View {
        let snapshot = model.snapshot
        VStack(spacing: 12) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                MetricTile(symbol: "cpu", title: model.text(.processor),
                           value: snapshot.cpuReady ? model.percent(snapshot.cpu) : "—", numeric: snapshot.cpu,
                           tint: loadTint(snapshot.cpu)) {
                    Sparkline(values: model.cpuHistory, tint: loadTint(snapshot.cpu))
                }
                MetricTile(symbol: "memorychip", title: model.text(.memory),
                           value: model.percent(snapshot.memoryFraction * 100), numeric: snapshot.memoryFraction,
                           tint: pressureTint(snapshot.pressure)) {
                    TileDetail(model.format(.memoryOf, model.gigabytes(snapshot.memoryUsed), model.gigabytes(snapshot.memoryTotal)))
                    TileDetail(pressureText(snapshot.pressure), tint: pressureTint(snapshot.pressure))
                    if snapshot.swapUsed > 64 * 1_048_576 {
                        TileDetail(model.format(.swapUsed, model.gigabytes(snapshot.swapUsed)))
                    }
                }
                BatteryTile(model: model, battery: snapshot.battery)
                MetricTile(symbol: "thermometer.medium", title: model.text(.temperature),
                           value: snapshot.temperature.map { model.celsius($0) } ?? "—", numeric: snapshot.temperature ?? 0,
                           tint: heatTint(snapshot.temperature)) {
                    TileDetail(snapshot.temperature == nil ? model.text(.noSensor) : model.text(.chipSensor))
                    TileDetail(fanSummary(snapshot))
                }
            }
            BusiestCard(model: model)
            FansCard(model: model, fans: snapshot.fans, read: snapshot.fansRead)
        }
    }

    private func loadTint(_ load: Double) -> Color {
        load >= 85 ? Palette.danger : load >= 60 ? Palette.warning : Palette.accent
    }

    private func pressureTint(_ pressure: MemoryPressure) -> Color {
        switch pressure {
        case .normal: Palette.positive
        case .warning: Palette.warning
        case .critical: Palette.danger
        }
    }

    private func heatTint(_ celsius: Double?) -> Color {
        guard let celsius else { return Palette.ink }
        return celsius >= 95 ? Palette.danger : celsius >= 80 ? Palette.warning : Palette.positive
    }

    private func pressureText(_ pressure: MemoryPressure) -> String {
        switch pressure {
        case .normal: model.text(.pressureNormal)
        case .warning: model.text(.pressureWarning)
        case .critical: model.text(.pressureCritical)
        }
    }

    private func fanSummary(_ snapshot: SystemSnapshot) -> String {
        guard !snapshot.fans.isEmpty else { return model.text(.fanNone) }
        let fastest = snapshot.fans.map(\.actual).max() ?? 0
        if fastest < 1 { return model.text(.fansIdle) }
        return "\(model.text(.fans)): \(model.format(.fanSpeed, model.integer(Int(fastest.rounded()))))"
    }
}

private struct TileDetail: View {
    let text: String
    var tint: Color = Palette.secondary

    init(_ text: String, tint: Color = Palette.secondary) {
        self.text = text
        self.tint = tint
    }

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(tint)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
    }
}

private struct MetricTile<Footer: View>: View {
    let symbol: String
    let title: String
    let value: String
    let numeric: Double
    var tint: Color = Palette.ink
    @ViewBuilder var footer: () -> Footer

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.secondary)
                    .lineLimit(1)
            }
            Text(value)
                .font(.system(size: 26, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText(value: numeric))
                .animation(.snappy(duration: 0.25), value: numeric)
            Spacer(minLength: 0)
            footer()
        }
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
        .card(radius: 18, padding: 14)
        .accessibilityElement(children: .combine)
    }
}

private struct BatteryTile: View {
    var model: AppModel
    let battery: BatteryInfo

    var body: some View {
        MetricTile(symbol: battery.charging ? "bolt.fill" : "battery.75percent", title: model.text(.battery),
                   value: battery.present ? model.percent(battery.percent) : "—", numeric: battery.percent,
                   tint: battery.percent <= 15 && !battery.onAdapter ? Palette.danger : Palette.positive) {
            TileDetail(state)
            if let health = battery.health {
                TileDetail(model.format(.healthLine, model.percent(health), battery.cycles.map { model.integer($0) } ?? "—"))
            }
        }
    }

    private var state: String {
        guard battery.present else { return model.text(.srcNone) }
        if battery.charging {
            if let full = battery.minutesToFull { return model.format(.timeToFull, model.duration(Double(full * 60))) }
            return model.text(.srcCharging)
        }
        if battery.onAdapter { return model.text(.srcAdapter) }
        if let left = battery.minutesToEmpty { return model.format(.timeLeft, model.duration(Double(left * 60))) }
        return model.text(.srcBattery)
    }
}

private struct BusiestCard: View {
    var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardTitle(model.text(.busiestApps))
            if model.busiest.isEmpty {
                HStack(spacing: 8) {
                    Spinner(size: 12, color: Palette.secondary)
                    Text(model.text(.measuring))
                        .font(.system(size: 12.5))
                        .foregroundStyle(Palette.secondary)
                }
                .padding(.vertical, 4)
            } else {
                let top = max(model.busiest.first?.cpu ?? 1, 1)
                ForEach(model.busiest) { app in
                    HStack(spacing: 12) {
                        AppIconView(path: app.appPath, size: 26, fallback: "gearshape.2")
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(app.name)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(Palette.ink)
                                    .lineLimit(1)
                                Spacer()
                                Text(model.percent(app.cpu))
                                    .font(.system(size: 12.5, weight: .semibold).monospacedDigit())
                                    .foregroundStyle(Palette.secondary)
                            }
                            LevelBar(fraction: app.cpu / top, tint: Palette.accent, height: 4)
                        }
                    }
                }
            }
        }
        .card()
    }
}

private struct FansCard: View {
    var model: AppModel
    let fans: [FanReading]
    let read: Bool

    var body: some View {
        let control = model.fans
        VStack(alignment: .leading, spacing: 12) {
            CardTitle(FanPhrases.title.text) {
                if control.installed && !fans.isEmpty {
                    Text(state(control))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(control.holding != nil ? Palette.accent : Palette.secondary)
                        .lineLimit(1)
                }
            }
            if fans.isEmpty {
                Text(read ? model.text(.fanNone) : model.text(.measuring))
                    .font(.system(size: 12.5))
                    .foregroundStyle(Palette.secondary)
            }
            ForEach(fans) { fan in
                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .firstTextBaseline) {
                        Image(systemName: "fanblades")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Palette.accent)
                            .modifier(FanSpin(active: fan.actual > 1))
                        Text(model.format(.fanName, model.integer(fan.id + 1)))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Palette.ink)
                        Spacer()
                        Text(fan.actual < 1 ? model.text(.fanStopped) : model.format(.fanSpeed, model.integer(Int(fan.actual.rounded()))))
                            .font(.system(size: 13, weight: .semibold).monospacedDigit())
                            .foregroundStyle(fan.actual < 1 ? Palette.secondary : Palette.ink)
                            .contentTransition(.numericText(value: fan.actual))
                            .animation(.snappy(duration: 0.25), value: fan.actual)
                    }
                    LevelBar(fraction: fan.maximum > 0 ? fan.actual / fan.maximum : 0, tint: Palette.accent, height: 4)
                    Text(model.format(.fanRange, model.integer(Int(fan.minimum)), model.integer(Int(fan.maximum))))
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.tertiary)
                }
            }
            if !fans.isEmpty {
                Hairline()
                if control.installed {
                    CoolingControls(model: model, control: control, fans: fans)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(FanPhrases.enableBody.text)
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Spacer()
                            if control.busy { Spinner(size: 12, color: Palette.secondary) }
                            PillButton(title: FanPhrases.enable.text, symbol: "fanblades.fill", prominent: true) { control.install() }
                                .disabled(control.busy)
                        }
                    }
                }
                if let problem = control.problem {
                    InlineNotice(symbol: "exclamationmark.triangle.fill", text: problem)
                }
            }
            Footnote(control.installed ? FanPhrases.note.text : model.text(.fanNote))
        }
        .card()
        .animation(.panelSpring, value: control.mode)
        .animation(.panelSpring, value: control.installed)
    }

    private func state(_ control: FanControl) -> String {
        if let rpm = control.holding { return FanPhrases.holding(model.integer(rpm)) }
        if control.mode == .smart { return FanPhrases.smartWaiting(model.celsius(control.start)) }
        return FanPhrases.automatic.text
    }
}

/// Spins the fan glyph while the fan runs. The rotate effect needs macOS 15; earlier systems show the glyph still.
private struct FanSpin: ViewModifier {
    var active: Bool

    func body(content: Content) -> some View {
        if #available(macOS 15, *) {
            content.symbolEffect(.rotate, isActive: active)
        } else {
            content
        }
    }
}

/// The cooling modes and their settings, shown once the helper is installed.
private struct CoolingControls: View {
    var model: AppModel
    @Bindable var control: FanControl
    let fans: [FanReading]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GlassSegmented(items: FanControl.Mode.allCases.map { SegmentItem(value: $0, title: $0.title.text) },
                           selection: control.mode) { control.mode = $0 }
            switch control.mode {
            case .auto:
                EmptyView()
            case .max:
                EmptyView()
            case .smart:
                slider(FanPhrases.rise.text, value: $control.start, range: 45...85, label: model.celsius(control.start)) {
                    if control.full < control.start + 5 { control.full = min(control.start + 5, 100) }
                }
                slider(FanPhrases.top.text, value: $control.full, range: 55...100, label: model.celsius(control.full)) {
                    if control.start > control.full - 5 { control.start = max(control.full - 5, 45) }
                }
            case .manual:
                slider(FanPhrases.speed.text, value: $control.level, range: 0...1, label: model.format(.fanSpeed, model.integer(manualRPM))) {}
            }
            HStack {
                Spacer()
                PillButton(title: FanPhrases.remove.text, symbol: "trash") { control.uninstall() }
                    .disabled(control.busy)
            }
        }
    }

    private var manualRPM: Int {
        let low = fans.map(\.minimum).max() ?? 0
        let high = fans.map(\.maximum).min() ?? low
        return Int(low + (high - low) * control.level)
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, label: String, settle: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Palette.ink)
                Spacer()
                Text(label).font(.system(size: 12.5, weight: .semibold).monospacedDigit()).foregroundStyle(Palette.accent)
            }
            FineSlider(value: value.wrappedValue, range: range, onChange: { value.wrappedValue = range.upperBound > 1 ? $0.rounded() : $0 }, onEnd: settle)
        }
    }
}
