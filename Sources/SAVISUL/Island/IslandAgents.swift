import SwiftUI

struct IslandAgents: View {
    let suite: Suite

    var body: some View {
        let list = ordered
        let launcher = suite.launcher
        Group {
            if launcher.composing && !launcher.targets.isEmpty {
                AgentComposer(suite: suite, launcher: launcher)
            } else if list.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "sparkles").font(.system(size: 26, weight: .semibold)).foregroundStyle(Palette.tertiary)
                    Text(Phrase("No AI agents found", ru: "ИИ-агенты не найдены", uk: "ШІ-агентів не знайдено", fr: "Aucun agent IA trouvé").text)
                        .font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Palette.ink)
                    Text(Phrase("Claude Code, Codex, Cursor, OpenCode and Copilot appear here once they run on this Mac.",
                                ru: "Claude Code, Codex, Cursor, OpenCode и Copilot появятся здесь, как только поработают на этом Mac.",
                                uk: "Claude Code, Codex, Cursor, OpenCode і Copilot зʼявляться тут, щойно попрацюють на цьому Mac.",
                                fr: "Claude Code, Codex, Cursor, OpenCode et Copilot apparaissent ici dès qu’ils tournent sur ce Mac.").text)
                        .font(.system(size: 11.5)).foregroundStyle(Palette.secondary).multilineTextAlignment(.center).frame(width: 380)
                    if !launcher.targets.isEmpty {
                        NewTaskButton { launcher.begin(nil, monitor: suite.agents) }
                            .padding(.top, 4)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: Self.gap) {
                    SummaryBar(suite: suite)
                    Grid(horizontalSpacing: Self.gap, verticalSpacing: Self.gap) {
                        let shown = Array(list.prefix(Self.limit))
                        ForEach(Array(stride(from: 0, to: shown.count, by: 2)), id: \.self) { row in
                            GridRow {
                                ForEach(shown[row..<min(row + 2, shown.count)]) { agent in
                                    let launchable = launcher.targets.contains { $0.kind == agent.kind }
                                    AgentCard(agent: agent, launchable: launchable) {
                                        launcher.begin(agent.kind, monitor: suite.agents)
                                    }
                                }
                                // An odd last card keeps its column width instead of stretching across.
                                if row + 1 >= shown.count { Color.clear.frame(height: Self.cardHeight) }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, Self.top)
                .padding(.bottom, Self.bottom)
            }
        }
        .onAppear { suite.launcher.refresh() }
    }

    static let limit = 4
    static let gap: CGFloat = 8
    static let cardHeight: CGFloat = 86
    private static let top: CGFloat = 8
    private static let bottom: CGFloat = 14
    private static let summary: CGFloat = 22

    /// Exactly the room the cards need, so the last row never ends under the island's edge.
    @MainActor static var height: CGFloat {
        let count = min(Suite.shared.agents.installed.count, limit)
        guard count > 0 else { return 200 }
        let rows = CGFloat((count + 1) / 2)
        return top + summary + gap + rows * cardHeight + (rows - 1) * gap + bottom
    }

    private var ordered: [AgentStatus] {
        suite.agents.installed.sorted { lhs, rhs in
            if lhs.working != rhs.working { return lhs.working }
            return (lhs.lastActive ?? .distantPast) > (rhs.lastActive ?? .distantPast)
        }
    }
}

private struct SummaryBar: View {
    let suite: Suite

    var body: some View {
        let monitor = suite.agents
        HStack(spacing: 10) {
            let working = monitor.working
            if working.isEmpty {
                Label(Phrase("All agents idle", ru: "Все агенты свободны", uk: "Усі агенти вільні", fr: "Tous les agents sont libres").text, systemImage: "moon.zzz.fill")
            } else {
                Label(Phrase("Working: %@", ru: "Работают: %@", uk: "Працюють: %@", fr: "Au travail : %@")(working.map(\.kind.short).joined(separator: ", ")),
                      systemImage: "bolt.fill")
                    .foregroundStyle(Palette.positive)
            }
            Spacer()
            let tokens = monitor.tokensToday
            if tokens > 0 {
                Text(Phrase("%@ tokens today", ru: "%@ токенов сегодня", uk: "%@ токенів сьогодні", fr: "%@ jetons aujourd’hui")(Say.compact(tokens)))
            }
            let code = monitor.code(week: false)
            if !code.isEmpty {
                CodeLine(code: code)
            }
            let cost = monitor.agents.compactMap(\.costToday).reduce(0, +)
            if cost > 0.01 {
                Text("≈ " + Say.money(cost)).foregroundStyle(Palette.accent)
                    .help(Phrase("At API list prices", ru: "По ценам API", uk: "За цінами API", fr: "Aux tarifs de l’API").text)
            }
            if !suite.launcher.targets.isEmpty {
                NewTaskButton { suite.launcher.begin(nil, monitor: monitor) }
            }
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(Palette.secondary)
        .labelStyle(.titleAndIcon)
        .frame(height: 22)
    }
}

private struct NewTaskButton: View {
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "plus").font(.system(size: 9.5, weight: .bold))
                Text(AgentPhrases.newTask.text).font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(Palette.onLight)
            .padding(.horizontal, 10)
            .frame(height: 22)
            .background(Capsule().fill(hover ? Palette.ink : Palette.accent))
        }
        .buttonStyle(PressableStyle())
        .onHover { hover = $0 }
    }
}

// MARK: Task composer

/// Pick an installed agent, write the task, pick the project, start it in a new Terminal window.
private struct AgentComposer: View {
    let suite: Suite
    @Bindable var launcher: AgentLauncher
    @FocusState private var focused: Bool

    var body: some View {
        let kind = launcher.target?.kind ?? .claude
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                ForEach(launcher.targets) { target in
                    AgentChoice(kind: target.kind, selected: target.kind == kind) {
                        withAnimation(.islandQuick) { launcher.selected = target.kind }
                        focused = true
                    }
                }
                Spacer(minLength: 8)
                Button(action: close) {
                    Image(systemName: "xmark").font(.system(size: 10.5, weight: .bold)).foregroundStyle(Palette.secondary)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(PressableStyle())
                .help(AgentPhrases.close.text)
            }
            VStack(spacing: 0) {
                TextField(AgentPhrases.placeholder(kind.title), text: $launcher.draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13.5))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(3, reservesSpace: true)
                    .focused($focused)
                    .onSubmit(send)
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
                    .padding(.bottom, 10)
                Hairline()
                HStack(spacing: 10) {
                    ProjectButton(launcher: launcher, choose: chooseFolder)
                    Spacer(minLength: 8)
                    Text(AgentPhrases.hint.text)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Palette.tertiary)
                        .lineLimit(1)
                    StartButton(enabled: launcher.canSend, action: send)
                }
                .padding(.horizontal, 10)
                .frame(height: 44)
            }
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.07)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(focused ? kind.tint.opacity(0.55) : Color.white.opacity(0.1), lineWidth: 0.8))
            if launcher.target?.style == .app || launcher.target?.style == .clipboard {
                Label(AgentPhrases.pasteNote.text, systemImage: "doc.on.clipboard")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Palette.tertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 14)
        .onAppear {
            suite.island.hold()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { focused = true }
        }
        .onDisappear {
            launcher.composing = false
            suite.island.release()
        }
        .onExitCommand(perform: close)
    }

    private func close() {
        withAnimation(.islandQuick) { launcher.cancel() }
    }

    private func chooseFolder() {
        launcher.chooseFolder {
            suite.island.hold()
            focused = true
        }
    }

    private func send() {
        guard launcher.canSend else {
            NSSound.beep()
            return
        }
        guard launcher.projectExists else {
            chooseFolder()
            return
        }
        guard let outcome = launcher.send() else { return }
        switch outcome {
        case .started(let kind, let project):
            suite.notify(IslandNotice(symbol: "paperplane.fill", tint: kind.tint, title: AgentPhrases.started(kind.title),
                                      detail: project, style: .success, duration: 4))
        case .pasteReady(let kind, let project):
            suite.notify(IslandNotice(symbol: "doc.on.clipboard.fill", tint: kind.tint, title: AgentPhrases.paste(kind.title),
                                      detail: project, style: .success, duration: 5))
        case .failed(let kind):
            suite.notify(IslandNotice(symbol: "exclamationmark.triangle.fill", tint: Palette.warning, title: AgentPhrases.failed(kind.title),
                                      detail: nil, style: .warning, duration: 5))
        }
    }
}

private struct AgentChoice: View {
    let kind: AgentKind
    let selected: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                AgentGlyph(kind: kind, size: 18, working: false)
                Text(kind.title).font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(selected ? Palette.ink : Palette.secondary)
            }
            .padding(.leading, 5)
            .padding(.trailing, 11)
            .frame(height: 28)
            .background(Capsule().fill(selected ? kind.tint.opacity(0.2) : Color.white.opacity(hover ? 0.1 : 0.06)))
            .overlay(Capsule().strokeBorder(selected ? kind.tint.opacity(0.5) : Color.clear, lineWidth: 0.8))
        }
        .buttonStyle(PressableStyle())
        .onHover { hover = $0 }
    }
}

/// The project folder, with a menu of recent ones and a folder picker.
private struct ProjectButton: View {
    let launcher: AgentLauncher
    let choose: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: showMenu) {
            HStack(spacing: 6) {
                Image(systemName: "folder.fill").font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.accent)
                Text(launcher.project?.lastPathComponent ?? AgentPhrases.noProject.text)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(launcher.project == nil ? Palette.secondary : Palette.ink)
                    .lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).foregroundStyle(Palette.secondary)
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(Capsule().fill(Color.white.opacity(hover ? 0.12 : 0.08)))
        }
        .buttonStyle(PressableStyle())
        .onHover { hover = $0 }
        .help(launcher.project.map { ProjectMenu.short($0.path) } ?? AgentPhrases.noProject.text)
    }

    private func showMenu() {
        ProjectMenu.shared.show(projects: launcher.projects, current: launcher.project,
                                pick: { launcher.pick($0) }, choose: choose)
    }
}

/// An NSMenu at the pointer: SwiftUI menus can't be styled inside the island.
@MainActor
private final class ProjectMenu: NSObject {
    static let shared = ProjectMenu()
    private var actions: [() -> Void] = []

    static func short(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    func show(projects: [URL], current: URL?, pick: @escaping (URL) -> Void, choose: @escaping () -> Void) {
        actions = []
        let menu = NSMenu()
        menu.autoenablesItems = false
        for url in projects {
            let item = NSMenuItem(title: url.lastPathComponent, action: #selector(run(_:)), keyEquivalent: "")
            item.target = self
            item.tag = actions.count
            item.state = url == current ? .on : .off
            item.toolTip = Self.short(url.path)
            let detail = NSAttributedString(string: "  " + Self.short(url.deletingLastPathComponent().path),
                                            attributes: [.foregroundColor: NSColor.secondaryLabelColor, .font: NSFont.systemFont(ofSize: 11)])
            let title = NSMutableAttributedString(string: url.lastPathComponent, attributes: [.font: NSFont.menuFont(ofSize: 13)])
            title.append(detail)
            item.attributedTitle = title
            actions.append { pick(url) }
            menu.addItem(item)
        }
        if !projects.isEmpty { menu.addItem(.separator()) }
        let other = NSMenuItem(title: AgentPhrases.chooseFolder.text, action: #selector(run(_:)), keyEquivalent: "")
        other.target = self
        other.tag = actions.count
        actions.append(choose)
        menu.addItem(other)
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    @objc private func run(_ sender: NSMenuItem) {
        guard actions.indices.contains(sender.tag) else { return }
        actions[sender.tag]()
    }
}

private struct StartButton: View {
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(AgentPhrases.send.text).font(.system(size: 12.5, weight: .semibold))
                Image(systemName: "arrow.up").font(.system(size: 10.5, weight: .bold))
            }
            .foregroundStyle(enabled ? Palette.onLight : Palette.tertiary)
            .padding(.horizontal, 14)
            .frame(height: 30)
            .background(Capsule().fill(enabled ? Palette.ink : Color.white.opacity(0.1)))
        }
        .buttonStyle(PressableStyle())
        .disabled(!enabled)
        .animation(.islandQuick, value: enabled)
    }
}

private struct AgentCard: View {
    let agent: AgentStatus
    var launchable = false
    var start: () -> Void = {}
    @State private var hover = false

    var body: some View {
        // Three fixed rows in every card, so neighbours line up whatever each agent has to say.
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                AgentGlyph(kind: agent.kind, size: 24, working: agent.working)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 5) {
                        Text(agent.kind.title).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Palette.ink).lineLimit(1)
                        if let plan = agent.plan {
                            Text(plan).font(.system(size: 9, weight: .bold)).foregroundStyle(agent.kind.tint)
                                .padding(.horizontal, 5).frame(height: 14)
                                .background(Capsule().fill(agent.kind.tint.opacity(0.15)))
                        }
                    }
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(state(at: context.date)).font(.system(size: 10.5, weight: agent.working ? .semibold : .regular).monospacedDigit())
                            .foregroundStyle(agent.limitHit ? Palette.danger : (agent.working ? Palette.positive : Palette.tertiary))
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                if agent.tokensToday > 0 {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(Say.compact(agent.tokensToday)).font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                            .foregroundStyle(Palette.ink)
                        Text(agent.costToday.map { "≈ " + Say.money($0) } ?? Phrase("tokens", ru: "токенов", uk: "токенів", fr: "jetons").text)
                            .font(.system(size: 9.5)).foregroundStyle(Palette.tertiary)
                    }
                    .help(Phrase("%@ tokens today · %@ more read from cache", ru: "%@ токенов сегодня · ещё %@ прочитано из кэша",
                                 uk: "%@ токенів сьогодні · ще %@ прочитано з кешу", fr: "%@ jetons aujourd’hui · %@ de plus lus du cache")(
                        Say.number(agent.tokensToday), Say.compact(agent.cacheToday)))
                }
            }
            .frame(height: 28)
            Text(detail ?? " ")
                .font(.system(size: 10.5)).foregroundStyle(Palette.secondary)
                .lineLimit(1).truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 6)
            Spacer(minLength: 0)
            // Narrow cards drop the second window rather than cut a number in half.
            ViewThatFits(in: .horizontal) {
                footer(limits: 2)
                footer(limits: 1)
                footer(limits: 0)
            }
            .frame(height: 20, alignment: .bottom)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity)
        .frame(height: IslandAgents.cardHeight)
        .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(Color.white.opacity(agent.working ? 0.09 : (launchable && hover ? 0.085 : 0.055))))
        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous)
            .strokeBorder(agent.working ? agent.kind.tint.opacity(0.35) : (launchable && hover ? agent.kind.tint.opacity(0.3) : Color.white.opacity(0.06)), lineWidth: 0.8))
        .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .onHover { inside in withAnimation(.islandQuick) { hover = inside } }
        .onTapGesture { if launchable { start() } }
        .help(launchable ? AgentPhrases.newTask.text : "")
    }

    private func footer(limits count: Int) -> some View {
        HStack(alignment: .bottom, spacing: 10) {
            if !agent.code.isEmpty {
                CodeLine(code: agent.code, size: 10)
                    .lineLimit(1)
                    .fixedSize()
            }
            Spacer(minLength: 0)
            ForEach(agent.limits.prefix(count)) { limit in
                LimitChip(limit: limit, tint: agent.kind.tint)
            }
        }
    }

    private func state(at date: Date) -> String {
        if agent.limitHit {
            if let until = agent.limitUntil {
                return Phrase("Limit · resets %@", ru: "Лимит · сброс в %@", uk: "Ліміт · скидання о %@", fr: "Limite · reprise à %@")(Say.time(until))
            }
            return Phrase("Usage limit reached", ru: "Лимит исчерпан", uk: "Ліміт вичерпано", fr: "Limite atteinte").text
        }
        if agent.working {
            let time = agent.since.map { Say.clock(date.timeIntervalSince($0)) } ?? ""
            let runs = agent.runs > 1 ? " · ×\(agent.runs)" : ""
            return Phrase("Working %@", ru: "Работает %@", uk: "Працює %@", fr: "Au travail %@")(time) + runs
        }
        if let last = agent.lastActive {
            let ago = date.timeIntervalSince(last)
            if ago < 90 { return Phrase("Idle · just now", ru: "Свободен · только что", uk: "Вільний · щойно", fr: "Libre · à l’instant").text }
            // Past a few hours "133 h 51 min" reads worse than "5 days ago".
            if ago >= 6 * 3600 { return Phrase("Idle · %@", ru: "Свободен · %@", uk: "Вільний · %@", fr: "Libre · %@")(Say.ago(last)) }
            return Phrase("Idle · %@ ago", ru: "Свободен · %@ назад", uk: "Вільний · %@ тому", fr: "Libre · il y a %@")(Say.duration(ago))
        }
        return Phrase("No sessions yet", ru: "Сессий ещё не было", uk: "Сесій ще не було", fr: "Aucune session")
            .text
    }

    private var detail: String? {
        var parts: [String] = []
        if let project = agent.project { parts.append(project) }
        if let model = agent.model { parts.append(model) }
        if agent.working, let task = agent.task { parts.append("«\(task)»") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// A usage window in one compact line: "5 h 1.2M" or "Week 34%" with a thin bar under it.
/// A usage window in one compact line: "5 h 1.2M", or "Week 34%" over a thin bar when there's a share to show.
private struct LimitChip: View {
    let limit: AgentLimit
    let tint: Color

    var body: some View {
        Group {
            if let used = limit.used {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        title
                        Spacer(minLength: 0)
                        number
                    }
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.1))
                            Capsule().fill(color).frame(width: max(3, proxy.size.width * min(used, 1)))
                        }
                    }
                    .frame(height: 3)
                }
                .frame(width: 72)
            } else {
                HStack(spacing: 4) {
                    title
                    number
                }
                .fixedSize()
            }
        }
        .help(limit.resets.map { Phrase("Resets %@", ru: "Сброс %@", uk: "Скидання %@", fr: "Reprise %@")(Self.when($0)) } ?? label)
    }

    private var title: some View {
        Text(label).font(.system(size: 9.5, weight: .semibold)).foregroundStyle(Palette.tertiary).lineLimit(1)
    }

    private var number: some View {
        Text(value).font(.system(size: 10, weight: .semibold, design: .rounded).monospacedDigit()).foregroundStyle(color).fixedSize()
    }

    private var label: String {
        switch limit.window {
        case .minutes(let minutes) where minutes >= 10_000: Phrase("Week", ru: "Неделя", uk: "Тиждень", fr: "Semaine").text
        case .minutes(let minutes): Phrase("%d h", ru: "%d ч", uk: "%d год", fr: "%d h")(max(minutes / 60, 1))
        case .days(let days): Phrase("%d d", ru: "%d дн.", uk: "%d дн.", fr: "%d j")(days)
        }
    }

    private var value: String {
        if let used = limit.used { return Say.percent(used * 100) }
        if let tokens = limit.tokens { return Say.compact(tokens) }
        return "—"
    }

    private var color: Color {
        guard let used = limit.used else { return Palette.ink }
        if used >= 0.9 { return Palette.danger }
        if used >= 0.7 { return Palette.warning }
        return tint
    }

    @MainActor static func when(_ date: Date) -> String {
        let interval = date.timeIntervalSinceNow
        if interval < 3600 * 20 { return Say.time(date) }
        let formatter = DateFormatter()
        formatter.locale = Suite.shared.language.locale
        formatter.setLocalizedDateFormatFromTemplate("EEE HH:mm")
        return formatter.string(from: date)
    }
}
