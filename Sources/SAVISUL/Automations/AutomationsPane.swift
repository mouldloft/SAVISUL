import AppKit
import SwiftUI

// MARK: Entry in Tools

/// The Tools tab's way in: how many automations run and the latest one that fired.
struct AutomationsEntry: View {
    var model: AppModel
    let engine: AutomationEngine

    var body: some View {
        Button { model.select(.automations) } label: {
            HStack(spacing: 12) {
                RowIcon(symbol: "point.3.filled.connected.trianglepath.dotted", tint: Palette.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(AutomationPhrases.title.text).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Palette.ink)
                    Text(AutomationsPhrases.subtitle(engine.items)).font(.system(size: 11.5)).foregroundStyle(Palette.secondary).lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .card()
    }
}

// MARK: Pane

/// Panel renders (--dump-panels) show the editor on a template without saving anything.
@MainActor
@Observable
final class AutomationsPreview {
    static let shared = AutomationsPreview()
    var automation: Automation?
}

struct AutomationsPane: View {
    var model: AppModel
    let engine: AutomationEngine
    @State private var editing: UUID?
    var body: some View {
        Group {
            if let preview = AutomationsPreview.shared.automation {
                AutomationEditor(engine: engine, automation: preview) {}
            } else if let id = editing, let item = engine.items.first(where: { $0.id == id }) {
                AutomationEditor(engine: engine, automation: item) { withAnimation(.panelSpring) { editing = nil } }
                    .id(id)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            } else {
                list.transition(.opacity)
            }
        }
    }

    private var list: some View {
        VStack(spacing: 12) {
            intro
            if !engine.items.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(engine.items.enumerated()), id: \.element.id) { index, item in
                        AutomationRow(item: item, running: engine.running.contains(item.id),
                                      toggle: { engine.setEnabled(item.id, !item.enabled) },
                                      open: { withAnimation(.panelSpring) { editing = item.id } })
                        if index < engine.items.count - 1 { Hairline(inset: 44) }
                    }
                }
                .card(padding: 12)
            }
            templates
            if !engine.history.isEmpty { recent }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                RowIcon(symbol: "point.3.filled.connected.trianglepath.dotted", tint: Palette.accent, size: 34)
                VStack(alignment: .leading, spacing: 3) {
                    Text(AutomationsPhrases.lead.text).font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.ink)
                    Text(AutomationsPhrases.leadDetail.text).font(.system(size: 12)).foregroundStyle(Palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !Suite.shared.settings.automations {
                HStack(spacing: 8) {
                    Image(systemName: "pause.circle.fill").foregroundStyle(Palette.warning)
                    Text(AutomationsPhrases.paused.text).font(.system(size: 12)).foregroundStyle(Palette.ink)
                    Spacer()
                    PillButton(title: AutomationsPhrases.turnOn.text, prominent: true) { Suite.shared.settings.automations = true }
                }
            }
            HStack {
                Spacer()
                PillButton(title: AutomationsPhrases.new.text, symbol: "plus", prominent: true) { create(Automation(name: AutomationsPhrases.untitled.text, trigger: AutomationTrigger(kind: .deviceConnected))) }
            }
        }
        .card(padding: 16)
    }

    private var templates: some View {
        VStack(alignment: .leading, spacing: 4) {
            CardTitle(AutomationsPhrases.templates.text) { EmptyView() }
                .padding(.bottom, 6)
            ForEach(Array(AutomationTemplates.all.enumerated()), id: \.offset) { index, template in
                Button { create(template) } label: {
                    HStack(spacing: 12) {
                        RowIcon(symbol: template.trigger.kind.symbol, tint: Palette.secondary, size: 30)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(template.name).font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.ink)
                            Text(AutomationsPhrases.summary(template)).font(.system(size: 11)).foregroundStyle(Palette.tertiary).lineLimit(1)
                        }
                        Spacer(minLength: 6)
                        Image(systemName: "plus.circle.fill").font(.system(size: 16)).foregroundStyle(Palette.accent)
                    }
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .card()
    }

    private var recent: some View {
        VStack(alignment: .leading, spacing: 8) {
            CardTitle(AutomationsPhrases.recent.text) { EmptyView() }
            ForEach(engine.history.prefix(5)) { record in
                HStack(spacing: 8) {
                    Image(systemName: record.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 12)).foregroundStyle(record.ok ? Palette.positive : Palette.warning)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(record.name).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Palette.ink).lineLimit(1)
                        if let detail = record.detail, !detail.isEmpty {
                            Text(detail).font(.system(size: 11)).foregroundStyle(Palette.tertiary).lineLimit(1).truncationMode(.middle)
                        }
                    }
                    Spacer(minLength: 6)
                    Text(Say.ago(record.date)).font(.system(size: 10.5)).foregroundStyle(Palette.tertiary)
                }
            }
        }
        .card()
    }

    private func create(_ automation: Automation) {
        let made = engine.add(automation)
        withAnimation(.panelSpring) { editing = made.id }
    }
}

private struct AutomationRow: View {
    let item: Automation
    let running: Bool
    let toggle: () -> Void
    let open: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            RowIcon(symbol: item.trigger.kind.symbol, tint: item.enabled ? Palette.accent : Palette.secondary, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.name).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Palette.ink).lineLimit(1)
                    if running { Spinner(size: 10, color: Palette.accent) }
                }
                Text(AutomationsPhrases.summary(item)).font(.system(size: 11)).foregroundStyle(Palette.secondary).lineLimit(2)
                if let last = item.lastRun {
                    Text(AutomationsPhrases.lastRun(Say.ago(last))).font(.system(size: 10.5)).foregroundStyle(Palette.tertiary)
                }
            }
            Spacer(minLength: 8)
            GlassSwitch(isOn: item.enabled, action: toggle)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
    }
}

// MARK: Editor

private struct AutomationEditor: View {
    let engine: AutomationEngine
    @State private var draft: Automation
    let close: () -> Void

    init(engine: AutomationEngine, automation: Automation, close: @escaping () -> Void) {
        self.engine = engine
        _draft = State(initialValue: automation)
        self.close = close
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Button(action: close) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left").font(.system(size: 11, weight: .bold))
                        Text(AutomationPhrases.title.text).font(.system(size: 12.5, weight: .semibold))
                    }
                    .foregroundStyle(Palette.accent)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer()
                PillButton(title: AutomationsPhrases.runNow.text, symbol: "play.fill") { engine.run(draft) }
                Menu {
                    Button(AutomationsPhrases.duplicate.text) {
                        var copy = draft
                        copy.name += " 2"
                        engine.add(copy)
                        close()
                    }
                    Button(AutomationsPhrases.delete.text, role: .destructive) {
                        engine.remove(draft.id)
                        close()
                    }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.ink)
                        .frame(width: 28, height: 28).background(Circle().fill(Color.white.opacity(0.08)))
                }
                .menuStyle(.button)
        .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
            }

            VStack(alignment: .leading, spacing: 10) {
                GlassField(prompt: AutomationsPhrases.namePrompt.text, text: $draft.name)
                switchRow(AutomationsPhrases.enabled.text, isOn: draft.enabled) { draft.enabled.toggle() }
                switchRow(AutomationsPhrases.island.text, isOn: draft.showInIsland) { draft.showInIsland.toggle() }
            }
            .card(padding: 14)

            section(AutomationsPhrases.when.text, symbol: "bolt.fill") {
                KindMenu(title: draft.trigger.kind.title.text, symbol: draft.trigger.kind.symbol) {
                    ForEach(AutomationTrigger.Kind.allCases, id: \.self) { kind in
                        Button { draft.trigger = AutomationTrigger(kind: kind, text: kind == .fileAdded ? "~/Downloads" : "", number: kind == .schedule ? 9 * 60 : 20) } label: {
                            Label(kind.title.text, systemImage: kind.symbol)
                        }
                    }
                }
                TriggerFields(trigger: $draft.trigger)
            }

            section(AutomationsPhrases.ifTitle.text, symbol: "line.3.horizontal.decrease", note: AutomationsPhrases.optional.text) {
                ForEach($draft.conditions) { $condition in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: condition.kind.symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.accent).frame(width: 18)
                            Text(condition.kind.title.text).font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.ink)
                            Spacer()
                            RemoveButton { draft.conditions.removeAll { $0.id == condition.id } }
                        }
                        ConditionFields(condition: $condition)
                    }
                    Hairline(inset: 0)
                }
                AddMenu(title: AutomationsPhrases.addCondition.text) {
                    ForEach(AutomationCondition.Kind.allCases, id: \.self) { kind in
                        Button { draft.conditions.append(AutomationCondition(kind: kind, number: kind == .timeBetween ? 9 * 60 : 20)) } label: {
                            Label(kind.title.text, systemImage: kind.symbol)
                        }
                    }
                }
            }

            section(AutomationsPhrases.doTitle.text, symbol: "play.fill") {
                ForEach(Array(draft.steps.enumerated()), id: \.element.id) { index, step in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Text("\(index + 1)").font(.system(size: 10, weight: .bold, design: .rounded)).foregroundStyle(Palette.onLight)
                                .frame(width: 18, height: 18).background(Circle().fill(Palette.accent))
                            Image(systemName: step.kind.symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.accent).frame(width: 16)
                            Text(step.kind.title.text).font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.ink).lineLimit(1)
                            Spacer(minLength: 4)
                            MoveButton(symbol: "chevron.up", enabled: index > 0) { draft.steps.swapAt(index, index - 1) }
                            MoveButton(symbol: "chevron.down", enabled: index < draft.steps.count - 1) { draft.steps.swapAt(index, index + 1) }
                            RemoveButton { draft.steps.remove(at: index) }
                        }
                        StepFields(step: $draft.steps[index], fileTrigger: draft.trigger.kind == .fileAdded)
                    }
                    Hairline(inset: 0)
                }
                AddMenu(title: AutomationsPhrases.addStep.text) {
                    ForEach(AutomationStep.Kind.allCases, id: \.self) { kind in
                        Button { draft.steps.append(Self.fresh(kind)) } label: { Label(kind.title.text, systemImage: kind.symbol) }
                    }
                }
            }

            Footnote(AutomationsPhrases.placeholders.text)
                .padding(.horizontal, 4)
        }
        .onChange(of: draft) { _, value in engine.update(value) }
    }

    private static func fresh(_ kind: AutomationStep.Kind) -> AutomationStep {
        switch kind {
        case .setVolume: AutomationStep(kind: kind, number: 35)
        case .wait: AutomationStep(kind: kind, number: 5)
        case .sound: AutomationStep(kind: kind, text: "Glass")
        case .renameFile: AutomationStep(kind: kind, text: "{date} {name}")
        case .moveFile: AutomationStep(kind: kind, text: "~/Documents")
        default: AutomationStep(kind: kind)
        }
    }

    private func switchRow(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        HStack {
            Text(title).font(.system(size: 13)).foregroundStyle(Palette.ink)
            Spacer()
            GlassSwitch(isOn: isOn, action: action)
        }
    }

    private func section<Content: View>(_ title: String, symbol: String, note: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.accent)
                Text(title).font(.system(size: 12, weight: .bold)).foregroundStyle(Palette.accent).textCase(.uppercase)
                if let note { Text(note).font(.system(size: 11)).foregroundStyle(Palette.tertiary) }
                Spacer()
            }
            content()
        }
        .card(padding: 14)
    }
}

// MARK: Fields

private struct TriggerFields: View {
    @Binding var trigger: AutomationTrigger

    var body: some View {
        switch trigger.kind {
        case .deviceConnected, .deviceDisconnected:
            DeviceField(text: $trigger.text, prompt: AutomationsPhrases.anyDevice.text)
        case .fileAdded:
            FolderField(path: $trigger.text)
            GlassField(prompt: AutomationsPhrases.extensions.text, text: $trigger.extensions)
        case .appLaunched, .appQuit:
            AppField(bundleID: $trigger.text, label: $trigger.label)
        case .agentFinished:
            AgentField(kind: $trigger.text)
        case .batteryBelow:
            PercentField(value: $trigger.number)
        case .powerConnected, .powerDisconnected:
            EmptyView()
        case .schedule:
            TimeField(minutes: $trigger.number)
            WeekdayField(days: $trigger.weekdays)
        }
    }
}

private struct ConditionFields: View {
    @Binding var condition: AutomationCondition

    var body: some View {
        switch condition.kind {
        case .batteryBelow, .batteryAbove: PercentField(value: $condition.number)
        case .onPower, .onBattery: EmptyView()
        case .appRunning, .appNotRunning: AppField(bundleID: $condition.text, label: $condition.label)
        case .timeBetween:
            HStack(spacing: 8) {
                TimeField(minutes: $condition.number)
                Text("—").foregroundStyle(Palette.tertiary)
                TimeField(minutes: $condition.number2)
            }
        case .weekdays: WeekdayField(days: $condition.weekdays)
        case .outputIs: DeviceField(text: $condition.text, prompt: AutomationsPhrases.deviceName.text)
        }
    }
}

private struct StepFields: View {
    @Binding var step: AutomationStep
    let fileTrigger: Bool

    var body: some View {
        switch step.kind {
        case .notice: GlassField(prompt: AutomationsPhrases.noticePrompt.text, text: $step.text)
        case .sound: SoundField(name: $step.text)
        case .setVolume: PercentField(value: $step.number)
        case .switchOutput: DeviceField(text: $step.text, prompt: AutomationsPhrases.deviceName.text)
        case .muteMics, .unmuteMics, .shelf: EmptyView()
        case .openApp, .quitApp: AppField(bundleID: $step.text, label: $step.label)
        case .openURL: GlassField(prompt: "https://…", text: $step.text)
        case .shortcut: ShortcutField(name: $step.text)
        case .feature: FeatureField(id: $step.text, on: $step.flag)
        case .action: ActionField(id: $step.text)
        case .renameFile:
            GlassField(prompt: "{date} {name}", text: $step.text)
            fileHint
        case .moveFile:
            FolderField(path: $step.text)
            fileHint
        case .wait:
            Stepper(value: $step.number, in: 1...600, step: step.number >= 60 ? 30 : 5) {
                Text(AutomationsPhrases.seconds(step.number)).font(.system(size: 12.5)).foregroundStyle(Palette.ink)
            }
        }
    }

    @ViewBuilder private var fileHint: some View {
        if !fileTrigger {
            Text(AutomationsPhrases.needsFileTrigger.text).font(.system(size: 11)).foregroundStyle(Palette.warning)
        }
    }
}

/// A capsule that opens a menu: the current choice, an icon and a chevron.
private struct KindMenu<Items: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let items: () -> Items

    var body: some View {
        Menu(content: items) {
            HStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.accent)
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.ink).lineLimit(1)
                Spacer(minLength: 6)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(Palette.tertiary)
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.white.opacity(0.07)))
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
    }
}

private struct AddMenu<Items: View>: View {
    let title: String
    @ViewBuilder let items: () -> Items

    var body: some View {
        Menu(content: items) {
            HStack(spacing: 5) {
                Image(systemName: "plus").font(.system(size: 10, weight: .bold))
                Text(title).font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(Palette.accent)
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

private struct RemoveButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Palette.secondary)
                .frame(width: 20, height: 20).background(Circle().fill(Color.white.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }
}

private struct MoveButton: View {
    let symbol: String
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 9, weight: .bold)).foregroundStyle(Palette.secondary)
                .frame(width: 20, height: 20).background(Circle().fill(Color.white.opacity(0.08)))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.3)
    }
}

/// Free text with a menu of the audio devices connected now.
private struct DeviceField: View {
    @Binding var text: String
    let prompt: String

    var body: some View {
        HStack(spacing: 6) {
            GlassField(prompt: prompt, text: $text)
            Menu {
                ForEach(Suite.shared.app?.audio.outputs ?? []) { device in
                    Button(device.name) { text = device.name }
                }
            } label: {
                Image(systemName: "list.bullet").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.ink)
                    .frame(width: 34, height: 34).background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.white.opacity(0.07)))
            }
            .menuStyle(.button)
        .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }
}

private struct FolderField: View {
    @Binding var path: String

    var body: some View {
        Button(action: choose) {
            HStack(spacing: 8) {
                Image(systemName: "folder.fill").font(.system(size: 12)).foregroundStyle(Palette.accent)
                Text(path.isEmpty ? AutomationsPhrases.chooseFolder.text : (AutomationEngine.expand(path) as NSString).abbreviatingWithTildeInPath)
                    .font(.system(size: 12.5, weight: .medium)).foregroundStyle(Palette.ink).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 4)
                Text(AutomationsPhrases.change.text).font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.accent)
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.black.opacity(0.28)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        if !path.isEmpty { panel.directoryURL = URL(fileURLWithPath: AutomationEngine.expand(path)) }
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url { path = (url.path as NSString).abbreviatingWithTildeInPath }
    }
}

private struct AppField: View {
    @Binding var bundleID: String
    @Binding var label: String

    var body: some View {
        KindMenu(title: label.isEmpty ? (bundleID.isEmpty ? AutomationsPhrases.chooseApp.text : bundleID) : label, symbol: "app") {
            ForEach(Self.running, id: \.bundleID) { app in
                Button(app.name) { bundleID = app.bundleID; label = app.name }
            }
            Divider()
            Button(AutomationsPhrases.otherApp.text, action: choose)
        }
    }

    private static var running: [(name: String, bundleID: String)] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .compactMap { app in app.bundleIdentifier.map { (app.localizedName ?? $0, $0) } }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url, let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { return }
        bundleID = id
        label = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }
}

private struct AgentField: View {
    @Binding var kind: String

    var body: some View {
        let current = AgentKind(rawValue: kind)
        KindMenu(title: current?.title ?? AutomationsPhrases.anyAgent.text, symbol: "sparkles") {
            Button(AutomationsPhrases.anyAgent.text) { kind = "" }
            Divider()
            ForEach(AgentKind.allCases, id: \.self) { agent in
                Button(agent.title) { kind = agent.rawValue }
            }
        }
    }
}

private struct PercentField: View {
    @Binding var value: Int

    var body: some View {
        HStack(spacing: 10) {
            Slider(value: Binding(get: { Double(value) }, set: { value = Int(($0 / 5).rounded() * 5) }), in: 0...100)
                .tint(Palette.accent)
            Text(Say.percent(Double(value))).font(.system(size: 12.5, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(Palette.ink).frame(width: 44, alignment: .trailing)
        }
    }
}

private struct TimeField: View {
    @Binding var minutes: Int

    var body: some View {
        HStack(spacing: 2) {
            Menu {
                ForEach(0..<24, id: \.self) { hour in Button(String(format: "%02d", hour)) { minutes = hour * 60 + minutes % 60 } }
            } label: { part(String(format: "%02d", minutes / 60 % 24)) }
            .menuStyle(.button)
        .buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
            Text(":").font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundStyle(Palette.tertiary)
            Menu {
                ForEach(Array(stride(from: 0, to: 60, by: 5)), id: \.self) { minute in Button(String(format: "%02d", minute)) { minutes = minutes / 60 * 60 + minute } }
            } label: { part(String(format: "%02d", minutes % 60)) }
            .menuStyle(.button)
        .buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        }
    }

    private func part(_ text: String) -> some View {
        Text(text).font(.system(size: 14, weight: .semibold, design: .rounded).monospacedDigit()).foregroundStyle(Palette.ink)
            .frame(width: 38, height: 30).background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white.opacity(0.08)))
    }
}

private struct WeekdayField: View {
    @Binding var days: [Int]

    var body: some View {
        let names = AutomationsPhrases.weekdays
        HStack(spacing: 4) {
            ForEach(1...7, id: \.self) { day in
                let on = days.contains(day)
                Button {
                    if on { days.removeAll { $0 == day } } else { days.append(day); days.sort() }
                } label: {
                    Text(names[day - 1]).font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(on ? Palette.onLight : Palette.secondary)
                        .frame(maxWidth: .infinity).frame(height: 26)
                        .background(Capsule().fill(on ? Palette.accent : Color.white.opacity(0.07)))
                }
                .buttonStyle(.plain)
            }
        }
        if days.isEmpty { Text(AutomationsPhrases.everyDay.text).font(.system(size: 11)).foregroundStyle(Palette.tertiary) }
    }
}

private struct SoundField: View {
    @Binding var name: String
    private static let sounds = ["Basso", "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero", "Morse", "Ping", "Pop", "Purr", "Sosumi", "Submarine", "Tink"]

    var body: some View {
        KindMenu(title: name.isEmpty ? "Glass" : name, symbol: "speaker.wave.2.fill") {
            ForEach(Self.sounds, id: \.self) { sound in
                Button(sound) {
                    name = sound
                    NSSound(named: NSSound.Name(sound))?.play()
                }
            }
        }
    }
}

/// The person's own Shortcuts, read once, plus free text for a name typed by hand.
private struct ShortcutField: View {
    @Binding var name: String
    @State private var shortcuts: [String] = []

    var body: some View {
        HStack(spacing: 6) {
            GlassField(prompt: AutomationsPhrases.shortcutPrompt.text, text: $name)
            Menu {
                if shortcuts.isEmpty { Text(AutomationsPhrases.noShortcuts.text) }
                ForEach(shortcuts, id: \.self) { item in Button(item) { name = item } }
            } label: {
                Image(systemName: "square.stack.3d.up").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.ink)
                    .frame(width: 34, height: 34).background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.white.opacity(0.07)))
            }
            .menuStyle(.button)
        .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .task {
            let output = await Task.detached(priority: .utility) { Shell.run("/usr/bin/shortcuts", ["list"], timeout: 10) }.value
            shortcuts = (output?.text ?? "").split(separator: "\n").map(String.init).filter { !$0.isEmpty }.sorted()
        }
    }
}

private struct FeatureField: View {
    @Binding var id: String
    @Binding var on: Bool

    var body: some View {
        let item = FeatureGroup.all.flatMap { [$0.main] + $0.options }.first { $0.id == id }
        VStack(alignment: .leading, spacing: 8) {
            KindMenu(title: item?.title.text ?? AutomationsPhrases.chooseFeature.text, symbol: "switch.2") {
                ForEach(FeatureGroup.all) { group in
                    Section(group.title.text) {
                        ForEach([group.main] + group.options) { feature in
                            Button(feature.title.text) { id = feature.id }
                        }
                    }
                }
            }
            GlassSegmented(items: [SegmentItem(value: true, title: AutomationsPhrases.on.text), SegmentItem(value: false, title: AutomationsPhrases.off.text)],
                           selection: on) { on = $0 }
        }
    }
}

private struct ActionField: View {
    @Binding var id: String

    var body: some View {
        let current = ActionRegistry.action(id)
        KindMenu(title: current.map { SuiteActions.title($0) } ?? AutomationsPhrases.chooseAction.text, symbol: current?.symbol ?? "wand.and.rays") {
            Section(AutomationsPhrases.quickActions.text) {
                ForEach(SuiteActions.all) { action in Button(SuiteActions.title(action)) { id = action.id } }
            }
            Section(AutomationsPhrases.fileActions.text) {
                ForEach(ContextCatalog.all.filter { !$0.accepts.isDisjoint(with: [.file, .image, .folder]) }) { action in
                    Button(action.title.text) { id = action.id }
                }
            }
        }
    }
}

// MARK: Copy

enum AutomationsPhrases {
    static let lead = Phrase("When → if → do", ru: "Когда → если → сделать", uk: "Коли → якщо → зробити", fr: "Quand → si → faire")
    static let leadDetail = Phrase("Something happens on the Mac and SAVISUL does the steps for you, even with the panel closed.",
                                   ru: "Что-то происходит на Mac — и SAVISUL сам выполняет шаги, даже при закрытой панели.",
                                   uk: "Щось відбувається на Mac — і SAVISUL сам виконує кроки, навіть із закритою панеллю.",
                                   fr: "Quelque chose se passe sur le Mac et SAVISUL fait les étapes, même panneau fermé.")
    static let paused = Phrase("Automations are off in Features", ru: "Автоматизации выключены в «Возможностях»", uk: "Автоматизації вимкнено в «Можливостях»", fr: "Automatisations coupées dans Fonctions")
    static let turnOn = Phrase("Turn on", ru: "Включить", uk: "Увімкнути", fr: "Activer")
    static let new = Phrase("New automation", ru: "Новая автоматизация", uk: "Нова автоматизація", fr: "Nouvelle automatisation")
    static let untitled = Phrase("New automation", ru: "Новая автоматизация", uk: "Нова автоматизація", fr: "Nouvelle automatisation")
    static let templates = Phrase("Templates", ru: "Шаблоны", uk: "Шаблони", fr: "Modèles")
    static let recent = Phrase("Recent runs", ru: "Последние запуски", uk: "Останні запуски", fr: "Derniers lancements")
    static let runNow = Phrase("Run now", ru: "Запустить", uk: "Запустити", fr: "Lancer")
    static let duplicate = Phrase("Duplicate", ru: "Дублировать", uk: "Дублювати", fr: "Dupliquer")
    static let delete = Phrase("Delete", ru: "Удалить", uk: "Видалити", fr: "Supprimer")
    static let namePrompt = Phrase("Name", ru: "Название", uk: "Назва", fr: "Nom")
    static let enabled = Phrase("On", ru: "Включена", uk: "Увімкнено", fr: "Active")
    static let island = Phrase("Show progress in the island", ru: "Показывать ход в островке", uk: "Показувати хід в острівці", fr: "Afficher la progression dans l’îlot")
    static let when = Phrase("When", ru: "Когда", uk: "Коли", fr: "Quand")
    static let ifTitle = Phrase("If", ru: "Если", uk: "Якщо", fr: "Si")
    static let doTitle = Phrase("Do", ru: "Сделать", uk: "Зробити", fr: "Faire")
    static let optional = Phrase("optional", ru: "необязательно", uk: "необовʼязково", fr: "facultatif")
    static let addCondition = Phrase("Condition", ru: "Условие", uk: "Умова", fr: "Condition")
    static let addStep = Phrase("Step", ru: "Шаг", uk: "Крок", fr: "Étape")
    static let anyDevice = Phrase("Any device, or a name like AirPods", ru: "Любое или название, например AirPods", uk: "Будь-який або назва, наприклад AirPods", fr: "N’importe lequel, ou un nom comme AirPods")
    static let deviceName = Phrase("Device name, like AirPods", ru: "Название, например AirPods", uk: "Назва, наприклад AirPods", fr: "Nom de l’appareil, comme AirPods")
    static let extensions = Phrase("File types: pdf, jpg (empty = any)", ru: "Типы файлов: pdf, jpg (пусто — любые)", uk: "Типи файлів: pdf, jpg (порожньо — будь-які)", fr: "Types : pdf, jpg (vide = tous)")
    static let chooseFolder = Phrase("Choose a folder", ru: "Выбрать папку", uk: "Вибрати теку", fr: "Choisir un dossier")
    static let change = Phrase("Change", ru: "Изменить", uk: "Змінити", fr: "Changer")
    static let chooseApp = Phrase("Choose an app", ru: "Выбрать приложение", uk: "Вибрати застосунок", fr: "Choisir une app")
    static let otherApp = Phrase("Other app…", ru: "Другое приложение…", uk: "Інший застосунок…", fr: "Autre app…")
    static let anyAgent = Phrase("Any agent", ru: "Любой агент", uk: "Будь-який агент", fr: "N’importe quel agent")
    static let everyDay = Phrase("Every day", ru: "Каждый день", uk: "Щодня", fr: "Tous les jours")
    static let noticePrompt = Phrase("Text, e.g. {agent} finished", ru: "Текст, например {agent} закончил", uk: "Текст, наприклад {agent} завершив", fr: "Texte, ex. {agent} a fini")
    static let shortcutPrompt = Phrase("Shortcut name", ru: "Название быстрой команды", uk: "Назва швидкої команди", fr: "Nom du raccourci")
    static let noShortcuts = Phrase("No shortcuts found", ru: "Быстрых команд нет", uk: "Швидких команд немає", fr: "Aucun raccourci")
    static let chooseFeature = Phrase("Choose a feature", ru: "Выбрать функцию", uk: "Вибрати функцію", fr: "Choisir une fonction")
    static let chooseAction = Phrase("Choose an action", ru: "Выбрать действие", uk: "Вибрати дію", fr: "Choisir une action")
    static let quickActions = Phrase("SAVISUL", ru: "SAVISUL", uk: "SAVISUL", fr: "SAVISUL")
    static let fileActions = Phrase("With the file", ru: "С файлом", uk: "З файлом", fr: "Avec le fichier")
    static let on = Phrase("Turn on", ru: "Включить", uk: "Увімкнути", fr: "Activer")
    static let off = Phrase("Turn off", ru: "Выключить", uk: "Вимкнути", fr: "Couper")
    static let needsFileTrigger = Phrase("Works when the trigger is a file in a folder", ru: "Работает, когда триггер — файл в папке", uk: "Працює, коли тригер — файл у теці", fr: "Fonctionne avec un fichier dans un dossier")
    static let placeholders = Phrase("Notices can use {file}, {agent}, {project}, {device}, {battery} and {app}. Renaming takes {name}, {date}, {time} and {n}.",
                                     ru: "В уведомлениях можно писать {file}, {agent}, {project}, {device}, {battery} и {app}. В имени файла — {name}, {date}, {time} и {n}.",
                                     uk: "У сповіщеннях можна писати {file}, {agent}, {project}, {device}, {battery} та {app}. В імені файлу — {name}, {date}, {time} і {n}.",
                                     fr: "Les notices acceptent {file}, {agent}, {project}, {device}, {battery} et {app}. Le renommage : {name}, {date}, {time}, {n}.")
    @MainActor static var weekdays: [String] {
        switch Suite.shared.language {
        case .en: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
        case .ru: ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"]
        case .uk: ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Нд"]
        case .fr: ["Lu", "Ma", "Me", "Je", "Ve", "Sa", "Di"]
        }
    }

    @MainActor static func seconds(_ value: Int) -> String {
        Phrase("Wait %d s", ru: "Ждать %d с", uk: "Чекати %d с", fr: "Attendre %d s")(value)
    }

    @MainActor static func lastRun(_ ago: String) -> String {
        Phrase("Last run %@", ru: "Последний запуск: %@", uk: "Останній запуск: %@", fr: "Dernier lancement %@")(ago)
    }

    /// "3 on · last 5 min ago", the pane's subtitle.
    @MainActor static func subtitle(_ items: [Automation]) -> String {
        guard !items.isEmpty else {
            return Phrase("None yet · start from a template", ru: "Пока нет · начните с шаблона", uk: "Поки немає · почніть із шаблону", fr: "Aucune · partez d’un modèle").text
        }
        let on = items.filter(\.enabled).count
        let count = Phrase("%d of %d on", ru: "Включено %d из %d", uk: "Увімкнено %d з %d", fr: "%d sur %d actives")(on, items.count)
        guard let last = items.compactMap(\.lastRun).max() else { return count }
        return count + " · " + Say.ago(last)
    }

    /// "AirPods connects → 3 steps".
    @MainActor static func summary(_ item: Automation) -> String {
        let trigger = item.trigger
        var when = trigger.kind.title.text
        switch trigger.kind {
        case .deviceConnected, .deviceDisconnected:
            if !trigger.text.isEmpty { when += " · \(trigger.text)" }
        case .fileAdded:
            when += " · " + (AutomationEngine.expand(trigger.text) as NSString).lastPathComponent
            if !trigger.extensions.isEmpty { when += " · \(trigger.extensions)" }
        case .appLaunched, .appQuit:
            if !trigger.label.isEmpty { when += " · \(trigger.label)" }
        case .agentFinished:
            when += " · " + (AgentKind(rawValue: trigger.text)?.title ?? anyAgent.text)
        case .batteryBelow:
            when += " " + Say.percent(Double(trigger.number))
        case .schedule:
            when += " " + AutomationEngine.clock(trigger.number)
        case .powerConnected, .powerDisconnected:
            break
        }
        let steps = Phrase("%d steps", ru: "шагов: %d", uk: "кроків: %d", fr: "%d étapes")(item.steps.count)
        return when + " → " + steps
    }
}
