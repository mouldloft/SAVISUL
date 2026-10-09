import SwiftUI

struct WorkPane: View {
    var model: AppModel
    @State private var showAllOther = false

    var body: some View {
        let rows = model.activity.rows(model.workRange)
        VStack(spacing: 12) {
            GlassSegmented(items: [SegmentItem(value: WorkRange.today, title: model.text(.today)),
                                   SegmentItem(value: WorkRange.week, title: model.text(.sevenDays))],
                           selection: model.workRange) { model.workRange = $0 }
            WorkSummary(model: model)
            TypingAccess(model: model)
            if rows.isEmpty {
                Footnote(model.text(.workEmpty))
                    .padding(.horizontal, 4)
            } else {
                UsageGroup(model: model, title: model.text(.groupEditors), rows: rows.filter { $0.category == .editor },
                           tint: Palette.accent, showsTyping: true)
                UsageGroup(model: model, title: model.text(.groupAssistants), rows: rows.filter { $0.category == .assistant },
                           tint: Palette.positive, showsTyping: true)
                UsageGroup(model: model, title: model.text(.groupOther), rows: rows.filter { $0.category == .other },
                           tint: Palette.ink.opacity(0.7), showsTyping: false, limit: showAllOther ? nil : 4) {
                    showAllOther.toggle()
                }
            }
            Footnote(WorkPhrases.note.text)
                .padding(.horizontal, 4)
        }
        .animation(.panelSpring, value: showAllOther)
    }
}

private struct WorkSummary: View {
    var model: AppModel

    var body: some View {
        let range = model.workRange
        let editors = model.activity.seconds(range, .editor)
        let assistants = model.activity.seconds(range, .assistant)
        let typing = model.activity.typing(range)
        let leaders = model.activity.rows(range).filter { $0.category == .editor }.prefix(3)
        let agents = Suite.shared.agents
        let aiTokens = agents.tokens(week: range == .week)
        let aiCode = agents.code(week: range == .week)
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.duration(editors))
                        .font(.system(size: 32, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(Palette.ink)
                        .contentTransition(.numericText(value: editors))
                    Text(model.text(.inEditors))
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.secondary)
                }
                Spacer()
                HStack(spacing: -8) {
                    ForEach(Array(leaders)) { usage in
                        AppIconView(bundleID: usage.bundleID, size: 34, fallback: "chevron.left.forwardslash.chevron.right")
                            .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
                    }
                }
            }
            HStack(spacing: 0) {
                stat(model.text(.typed), model.integer(typing.characters))
                    .help(WorkPhrases.typedHelp.text)
                divider
                stat(WorkPhrases.aiTokens.text, Say.compact(aiTokens))
                    .help(WorkPhrases.tokensHelp.text)
                divider
                stat(WorkPhrases.code.text, "+" + Say.compact(aiCode.added))
                    .help(CodeLine.help(aiCode))
                divider
                stat(model.text(.aiApps), model.duration(assistants))
            }
        }
        .card(padding: 18)
    }

    private var divider: some View {
        Rectangle().fill(Palette.hairline).frame(width: 0.5, height: 30)
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(Palette.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct TypingAccess: View {
    var model: AppModel

    var body: some View {
        let permissions = model.permissions
        if model.preview {
            EmptyView()
        } else if !permissions.accessibilityGranted {
            PermissionCallout(
                symbol: "keyboard",
                title: model.text(.keysTitle),
                message: permissions.accessibility == .notDetermined ? model.text(.keysBody) : model.text(.keysWaiting),
                actions: permissions.accessibility == .notDetermined
                    ? [CalloutAction(title: model.text(.allow), prominent: true) { model.requestTyping() }]
                    : [CalloutAction(title: model.text(.openSettings), prominent: true) { model.permissions.openSettings(.accessibility) }])
        } else if model.activity.typingFailed {
            PermissionCallout(symbol: "keyboard", title: model.text(.keysTitle), message: model.text(.keysFailed),
                              actions: [CalloutAction(title: model.text(.reopen), prominent: true) { model.permissions.relaunch() }])
        }
    }
}

private struct UsageGroup: View {
    var model: AppModel
    let title: String
    let rows: [AppUsage]
    let tint: Color
    let showsTyping: Bool
    var limit: Int? = nil
    var toggleMore: (() -> Void)? = nil

    var body: some View {
        if !rows.isEmpty {
            let visible = limit.map { Array(rows.prefix($0)) } ?? rows
            let longest = max(rows.first?.seconds ?? 1, 1)
            VStack(alignment: .leading, spacing: 12) {
                CardTitle(title) {
                    Text(model.duration(rows.reduce(0) { $0 + $1.seconds }))
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Palette.secondary)
                }
                ForEach(visible) { usage in
                    UsageRow(model: model, usage: usage, fraction: usage.seconds / longest, tint: tint, showsTyping: showsTyping)
                }
                if let toggleMore, rows.count > 4 {
                    Button(action: toggleMore) {
                        HStack(spacing: 4) {
                            Text(limit == nil ? model.text(.showLess) : model.format(.showMore, model.integer(rows.count - 4)))
                            Image(systemName: limit == nil ? "chevron.up" : "chevron.down")
                                .font(.system(size: 9.5, weight: .bold))
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.accent)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .card()
        }
    }
}

private struct UsageRow: View {
    var model: AppModel
    let usage: AppUsage
    let fraction: Double
    let tint: Color
    let showsTyping: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            AppIconView(bundleID: usage.bundleID, size: 30)
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(usage.name)
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(model.duration(usage.seconds))
                        .font(.system(size: 12.5, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Palette.ink)
                }
                LevelBar(fraction: fraction, tint: tint, height: 4)
                if showsTyping && usage.characters > 0 {
                    Text(WorkPhrases.typedChars(model.integer(usage.characters)))
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.secondary)
                }
                if let surface = AgentSurface.editor(usage.bundleID) {
                    let ai = Suite.shared.agents.usage(surface, week: model.workRange == .week)
                    if ai.model != nil || ai.tokens > 0 || !ai.code.isEmpty {
                        HStack(spacing: 6) {
                            if let name = ai.model {
                                Label(name, systemImage: "sparkles").labelStyle(CompactLabel())
                                    .foregroundStyle(Palette.accent)
                            }
                            if ai.tokens > 0 {
                                Text(WorkPhrases.tokens(Say.compact(ai.tokens))).foregroundStyle(Palette.secondary)
                                    .help(WorkPhrases.cacheHelp(Say.compact(ai.cache)))
                            }
                            if !ai.code.isEmpty { CodeLine(code: ai.code) }
                        }
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                    }
                }
            }
        }
    }
}

extension AgentSurface {
    /// The editor rows in Work that agent usage can be attached to.
    static func editor(_ bundleID: String) -> AgentSurface? {
        switch bundleID {
        case "com.microsoft.VSCode", "com.microsoft.VSCodeInsiders", "com.vscodium": .vscode
        case "com.todesktop.230313mzl4w4u92": .cursor
        default: nil
        }
    }
}

enum WorkPhrases {
    static let aiTokens = Phrase("AI tokens", ru: "ИИ-токены", uk: "ШІ-токени", fr: "Jetons IA")
    static let code = Phrase("Code", ru: "Код", uk: "Код", fr: "Code")
    static let typedHelp = Phrase("Characters you typed yourself. Keys only, never the text.",
                                  ru: "Знаки, которые вы набрали сами. Только счётчик, без текста.",
                                  uk: "Знаки, які ви набрали самі. Лише лічильник, без тексту.",
                                  fr: "Caractères tapés par vous. Le compte seulement, jamais le texte.")
    static let tokensHelp = Phrase("Tokens your AI agents used: input, output and cache writes. Cache reads are counted apart.",
                                   ru: "Токены ваших ИИ-агентов: вход, выход и запись в кэш. Чтение из кэша считается отдельно.",
                                   uk: "Токени ваших ШІ-агентів: вхід, вихід і запис у кеш. Читання з кешу рахується окремо.",
                                   fr: "Jetons utilisés par vos agents IA : entrée, sortie et écritures de cache. Les lectures de cache sont à part.")
    static let note = Phrase("AI tokens and code come from the agents’ own logs and Cursor’s AI tracking, inside each project folder. Cache reads aren’t counted as tokens.",
                             ru: "ИИ-токены и код берутся из журналов самих агентов и учёта ИИ в Cursor, только внутри папки проекта. Чтение из кэша не считается токенами.",
                             uk: "ШІ-токени й код беруться з журналів самих агентів і обліку ШІ в Cursor, лише в теці проєкту. Читання з кешу не рахується токенами.",
                             fr: "Les jetons et le code IA viennent des journaux des agents et du suivi IA de Cursor, dans chaque dossier de projet. Les lectures de cache ne comptent pas.")

    @MainActor static func typedChars(_ count: String) -> String {
        Phrase("%@ chars typed", ru: "набрано %@ симв.", uk: "набрано %@ симв.", fr: "%@ caractères tapés")(count)
    }
    @MainActor static func tokens(_ count: String) -> String {
        Phrase("%@ tokens", ru: "%@ токенов", uk: "%@ токенів", fr: "%@ jetons")(count)
    }
    @MainActor static func cacheHelp(_ count: String) -> String {
        Phrase("Plus %@ read from cache", ru: "Плюс %@ прочитано из кэша", uk: "Плюс %@ прочитано з кешу", fr: "Plus %@ lus du cache")(count)
    }
}
