import SwiftUI

struct ToolsPane: View {
    var model: AppModel

    var body: some View {
        VStack(spacing: 12) {
            AutomationsEntry(model: model, engine: Suite.shared.automations)
            CaptureCard(model: model)
            BrowserCard(model: model, link: model.browserLink)
            AlertsCard(model: model)
            UtilitiesCard(model: model, store: model.utilities)
        }
    }
}

private struct BrowserCard: View {
    var model: AppModel
    var link: BrowserLink

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                RowIcon(symbol: "menubar.rectangle", tint: Palette.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.text(.browserTitle))
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                    Text(status)
                        .font(.system(size: 11.5))
                        .foregroundStyle(link.installed ? Palette.positive : Palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if link.live {
                    Circle()
                        .fill(Palette.positive)
                        .frame(width: 7, height: 7)
                        .shadow(color: Palette.positive.opacity(0.6), radius: 4)
                        .transition(.opacity)
                }
            }
            if !link.installed {
                Hairline()
                VStack(alignment: .leading, spacing: 9) {
                    StepRow(number: 1, text: model.text(.browserStep1))
                    StepRow(number: 2, text: model.text(.browserStep2))
                    StepRow(number: 3, text: model.text(.browserStep3))
                }
            }
            HStack(spacing: 8) {
                Spacer()
                PillButton(title: model.text(.browserReveal), symbol: "folder") { BrowserIntegration.revealFolder() }
                PillButton(title: model.text(.browserOpen), symbol: "puzzlepiece.extension", prominent: !link.installed) {
                    BrowserIntegration.openExtensionsPage(browser: link.browser)
                }
            }
        }
        .card()
        .animation(.panelSpring, value: link.live)
        .animation(.panelSpring, value: link.installed)
    }

    private var status: String {
        if link.installed { return model.format(.browserConnected, link.browser ?? "Chrome") }
        return model.text(.browserIdle)
    }
}

private struct StepRow: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .font(.system(size: 10.5, weight: .bold).monospacedDigit())
                .foregroundStyle(Palette.accent)
                .frame(width: 18, height: 18)
                .background(Circle().fill(Palette.accent.opacity(0.14)))
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(Palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct CaptureCard: View {
    var model: AppModel

    var body: some View {
        let capture = model.capture
        VStack(alignment: .leading, spacing: 14) {
            CardTitle(model.text(.capture))
            HStack(spacing: 0) {
                CaptureButton(symbol: "rectangle.dashed", title: model.text(.capSelection)) { model.shoot(.selection) }
                CaptureButton(symbol: "macwindow", title: model.text(.capWindow)) { model.shoot(.window) }
                CaptureButton(symbol: "display", title: model.text(.capScreen)) { model.shoot(.screen) }
                CaptureButton(symbol: capture.isRecording ? "stop.fill" : "record.circle",
                              title: model.text(capture.isRecording ? .capStop : .capRecord), tint: Palette.danger,
                              active: capture.isRecording) { model.toggleRecording() }
                CaptureButton(symbol: "camera.viewfinder", title: model.text(.capToolbar)) { model.openCaptureToolbar() }
            }
            if !model.permissions.screenGranted && !model.preview {
                ScreenAccess(model: model)
            }
            if capture.last != nil {
                LastCapture(model: model)
            }
        }
        .card(padding: 16)
    }
}

private struct CaptureButton: View {
    let symbol: String
    let title: String
    var tint: Color = Palette.ink
    var active = false
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(active ? Palette.onLight : tint)
                    .frame(width: 50, height: 50)
                    .background(Circle().fill(active ? Palette.danger : Color.white.opacity(hover ? 0.1 : 0.02)))
                    .floatingGlass(Circle(), shadow: false)
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Palette.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .onHover { hover = $0 }
    }
}

private struct ScreenAccess: View {
    var model: AppModel

    var body: some View {
        let permissions = model.permissions
        if permissions.screen == .notDetermined {
            PermissionCallout(symbol: "rectangle.dashed.badge.record", title: model.text(.screenTitle), message: model.text(.screenBody),
                              actions: [CalloutAction(title: model.text(.allow), prominent: true) { permissions.requestScreenRecording() }])
        } else {
            PermissionCallout(symbol: "rectangle.dashed.badge.record", title: model.text(.screenTitle),
                              message: "\(model.text(.screenBody)) \(model.text(.screenAfter))",
                              actions: [CalloutAction(title: model.text(.openSettings), prominent: true) { permissions.openSettings(.screen) }])
        }
    }
}

private struct LastCapture: View {
    var model: AppModel

    var body: some View {
        let capture = model.capture
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.black.opacity(0.3))
                if let image = capture.thumbnail {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: capture.last?.isVideo == true ? "film" : "photo")
                        .foregroundStyle(Palette.tertiary)
                }
            }
            .frame(width: 54, height: 38)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
            VStack(alignment: .leading, spacing: 2) {
                Text(model.text(.lastCapture))
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Palette.secondary)
                Text(capture.last?.url.deletingPathExtension().lastPathComponent ?? "")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 6)
            GlassIconButton(symbol: capture.justCopied ? "checkmark" : "doc.on.doc", size: 30,
                            help: model.text(capture.justCopied ? .copied : .copyAgain)) { model.capture.copyLast() }
            GlassIconButton(symbol: "folder", size: 30, help: model.text(.revealInFinder)) { model.capture.reveal() }
            GlassIconButton(symbol: "arrow.up.forward.app", size: 30, help: model.text(.openFile)) { model.capture.open() }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.black.opacity(0.18)))
    }
}

private struct AlertsCard: View {
    var model: AppModel

    var body: some View {
        let alerts = model.alerts
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                RowIcon(symbol: "bell.badge", tint: Palette.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.text(.alertsTitle))
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                    Text(model.text(.alertsBody))
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                GlassSwitch(isOn: alerts.enabled) { model.toggleAlerts() }
                    .accessibilityLabel(model.text(.alertsTitle))
            }
            if alerts.enabled && model.permissions.notifications == .denied {
                PermissionCallout(symbol: "bell.slash", title: model.text(.permNotifications), message: model.text(.notifOff),
                                  actions: [CalloutAction(title: model.text(.openSettings), prominent: true) {
                                      model.permissions.openSettings(.notifications)
                                  }])
            }
            if alerts.enabled {
                Hairline()
                ThresholdRow(model: model, title: model.text(.alertCPU), value: alerts.cpuLimit, range: 50...100,
                             label: model.percent(alerts.cpuLimit)) { model.alerts.cpuLimit = $0 }
                ThresholdRow(model: model, title: model.text(.alertMemory), value: alerts.memoryLimit, range: 60...98,
                             label: model.percent(alerts.memoryLimit)) { model.alerts.memoryLimit = $0 }
                ThresholdRow(model: model, title: model.text(.alertBattery), value: alerts.batteryLimit, range: 5...50,
                             label: model.percent(alerts.batteryLimit)) { model.alerts.batteryLimit = $0 }
                ThresholdRow(model: model, title: model.text(.alertHeat), value: alerts.heatLimit, range: 60...105,
                             label: model.celsius(alerts.heatLimit)) { model.alerts.heatLimit = $0 }
                Hairline()
                ToggleRow(symbol: "flag.checkered", tint: Palette.positive, title: model.text(.alertDone),
                          detail: model.text(.alertDoneDetail), isOn: alerts.workDone) {
                    model.alerts.workDone.toggle()
                }
                HStack {
                    Spacer()
                    PillButton(title: model.text(.sendTest), symbol: "paperplane.fill") { model.sendTestAlert() }
                }
            }
        }
        .card()
        .animation(.panelSpring, value: alerts.enabled)
    }
}

private struct ThresholdRow: View {
    var model: AppModel
    let title: String
    let value: Double
    let range: ClosedRange<Double>
    let label: String
    let set: (Double) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Palette.ink)
                Spacer()
                Text(label)
                    .font(.system(size: 12.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Palette.accent)
            }
            FineSlider(value: value, range: range) { set($0.rounded()) }
        }
    }
}

private struct UtilitiesCard: View {
    var model: AppModel
    @Bindable var store: UtilityStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardTitle(model.text(.utilities)) {
                Text(model.integer(BuiltinUtility.allCases.count + store.items.count))
                    .font(.system(size: 11.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Palette.secondary)
                    .padding(.horizontal, 8)
                    .frame(height: 22)
                    .floatingGlass(Capsule(), shadow: false)
                GlassIconButton(symbol: store.adding ? "xmark" : "plus", size: 26, help: model.text(.addUtility)) {
                    store.adding.toggle()
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 14) {
                ForEach(BuiltinUtility.allCases) { utility in
                    UtilityTile(model: model, utility: utility)
                }
            }
            if !store.items.isEmpty {
                Hairline()
                ForEach(store.items) { item in
                    CustomUtilityRow(model: model, item: item, running: store.running.contains(item.id))
                }
            } else if !store.adding {
                Footnote(model.text(.utilitiesEmpty))
            }
            if store.adding {
                AddUtilityForm(model: model, store: store)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .card()
        .animation(.panelSpring, value: store.adding)
        .animation(.panelSpring, value: store.items)
    }
}

private struct UtilityTile: View {
    var model: AppModel
    let utility: BuiltinUtility
    @State private var hover = false

    var body: some View {
        Button { model.run(utility) } label: {
            VStack(spacing: 7) {
                ZStack {
                    Circle().fill(Color.white.opacity(hover ? 0.1 : 0.03))
                    if let path = utility.appPath {
                        AppIconView(path: path, size: 30)
                    } else {
                        Image(systemName: symbol)
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(utility == .hiddenFiles && model.utilities.hiddenFilesVisible ? Palette.accent : Palette.ink)
                    }
                }
                .frame(width: 48, height: 48)
                .floatingGlass(Circle(), shadow: false)
                Text(model.text(utility.title))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Palette.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .onHover { hover = $0 }
    }

    private var symbol: String {
        utility == .hiddenFiles ? (model.utilities.hiddenFilesVisible ? "eye" : "eye.slash") : utility.symbol
    }
}

private struct CustomUtilityRow: View {
    var model: AppModel
    let item: UtilityItem
    let running: Bool
    @State private var hover = false

    var body: some View {
        HStack(spacing: 12) {
            if item.isCommand {
                RowIcon(symbol: "terminal", tint: Palette.accent)
            } else {
                AppIconView(path: (item.target as NSString).expandingTildeInPath, size: 30)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Text(item.target)
                    .font(.system(size: 11, design: item.isCommand ? .monospaced : .default))
                    .foregroundStyle(Palette.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 6)
            if hover {
                GlassIconButton(symbol: "trash", size: 28, tint: Palette.danger, help: model.text(.remove)) {
                    model.utilities.remove(item.id)
                }
                .transition(.opacity)
            }
            if running {
                Spinner(size: 14)
                    .frame(width: 30, height: 30)
            } else {
                GlassIconButton(symbol: "play.fill", size: 30, help: model.text(.run)) { model.launch(item) }
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering in withAnimation(.quickSpring) { hover = hovering } }
    }
}

private struct AddUtilityForm: View {
    var model: AppModel
    @Bindable var store: UtilityStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GlassField(prompt: model.text(.fieldName), text: $store.draftName)
            GlassField(prompt: model.text(.fieldTarget), text: $store.draftTarget, monospaced: store.draftIsCommand)
            HStack(spacing: 8) {
                Button { store.draftIsCommand.toggle() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: store.draftIsCommand ? "checkmark.square.fill" : "square")
                            .foregroundStyle(store.draftIsCommand ? Palette.accent : Palette.secondary)
                        Text(model.text(.shellCommand))
                            .foregroundStyle(Palette.ink)
                    }
                    .font(.system(size: 12.5, weight: .medium))
                }
                .buttonStyle(.plain)
                Spacer()
                PillButton(title: model.text(.chooseApp)) { model.chooseUtilityApp() }
                PillButton(title: model.text(.addUtility), prominent: true) { store.add() }
                    .disabled(!store.canAdd)
                    .opacity(store.canAdd ? 1 : 0.5)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.black.opacity(0.18)))
    }
}
