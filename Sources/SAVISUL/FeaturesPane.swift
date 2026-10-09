import SwiftUI

// MARK: Model

/// One switch in the Features tab.
struct FeatureItem: Identifiable {
    let id: String
    let key: ReferenceWritableKeyPath<SuiteSettings, Bool>
    let title: Phrase
    var detail: Phrase?
    var keys: [String] = []
}

/// A group of features: a main switch, its options, and the permission it needs.
struct FeatureGroup: Identifiable {
    enum Needs { case nothing, accessibility, screen }

    let id: String
    let symbol: String
    let title: Phrase
    let detail: Phrase
    let main: FeatureItem
    let options: [FeatureItem]
    var needs: Needs = .nothing

    /// Options only count while the main switch is on: that is what is actually running.
    @MainActor func tally(_ settings: SuiteSettings) -> (on: Int, total: Int) {
        let mainOn = settings[keyPath: main.key]
        let on = (mainOn ? 1 : 0) + (mainOn ? options.filter { settings[keyPath: $0.key] }.count : 0)
        return (on, 1 + options.count)
    }

    @MainActor static let all: [FeatureGroup] = [
        FeatureGroup(
            id: "island", symbol: "capsule.inset.filled", title: Phrase("Island", ru: "Островок", uk: "Острівець", fr: "Îlot"),
            detail: Phrase("Music, meetings, timers, files and agents around the camera.", ru: "Музыка, встречи, таймеры, файлы и агенты вокруг камеры.",
                           uk: "Музика, зустрічі, таймери, файли й агенти навколо камери.", fr: "Musique, réunions, minuteurs, fichiers et agents autour de la caméra."),
            main: FeatureItem(id: "island", key: \.island, title: Phrase("Show the island", ru: "Показывать островок", uk: "Показувати острівець", fr: "Afficher l’îlot")),
            options: [
                FeatureItem(id: "islandHover", key: \.islandHover, title: Phrase("Open on hover", ru: "Открывать наведением", uk: "Відкривати наведенням", fr: "Ouvrir au survol")),
                FeatureItem(id: "islandMusic", key: \.islandMusic, title: Phrase("Now playing", ru: "Сейчас играет", uk: "Зараз грає", fr: "En lecture")),
                FeatureItem(id: "islandLyrics", key: \.islandLyrics, title: Phrase("Synced lyrics", ru: "Текст песни", uk: "Текст пісні", fr: "Paroles synchronisées"),
                            detail: Phrase("From lrclib.net, cached on this Mac", ru: "С lrclib.net, хранится на этом Mac", uk: "З lrclib.net, зберігається на цьому Mac", fr: "Depuis lrclib.net, gardées sur ce Mac")),
                FeatureItem(id: "islandEqualizer", key: \.islandEqualizer, title: Phrase("Equalizer", ru: "Эквалайзер", uk: "Еквалайзер", fr: "Égaliseur")),
                FeatureItem(id: "islandCalendar", key: \.islandCalendar, title: Phrase("Next meeting", ru: "Ближайшая встреча", uk: "Найближча зустріч", fr: "Prochaine réunion")),
                FeatureItem(id: "islandCalls", key: \.islandCalls, title: Phrase("Calls", ru: "Звонки", uk: "Дзвінки", fr: "Appels"),
                            detail: Phrase("Zoom, Teams, FaceTime, Meet and other calls, with a mute button",
                                           ru: "Zoom, Teams, FaceTime, Meet и другие звонки — с кнопкой выключения микрофона",
                                           uk: "Zoom, Teams, FaceTime, Meet та інші дзвінки — з кнопкою вимкнення мікрофона",
                                           fr: "Zoom, Teams, FaceTime, Meet et autres appels, avec un bouton pour couper le micro")),
                FeatureItem(id: "islandTimers", key: \.islandTimers, title: Phrase("Timers", ru: "Таймеры", uk: "Таймери", fr: "Minuteurs")),
                FeatureItem(id: "islandDownloads", key: \.islandDownloads, title: Phrase("Downloads", ru: "Загрузки", uk: "Завантаження", fr: "Téléchargements")),
                FeatureItem(id: "islandShelf", key: \.islandShelf, title: Phrase("Shelf in the island", ru: "Полка в островке", uk: "Полиця в острівці", fr: "Étagère dans l’îlot")),
                FeatureItem(id: "islandAgents", key: \.islandAgents, title: Phrase("AI agents", ru: "ИИ-агенты", uk: "ШІ-агенти", fr: "Agents IA"),
                            detail: Phrase("Claude Code, Codex, Cursor, OpenCode, Copilot", ru: "Claude Code, Codex, Cursor, OpenCode, Copilot",
                                           uk: "Claude Code, Codex, Cursor, OpenCode, Copilot", fr: "Claude Code, Codex, Cursor, OpenCode, Copilot")),
                FeatureItem(id: "islandCamera", key: \.islandCamera, title: Phrase("Camera mirror", ru: "Зеркало камеры", uk: "Дзеркало камери", fr: "Miroir de caméra")),
                FeatureItem(id: "islandNotices", key: \.islandNotices, title: Phrase("Notices", ru: "Уведомления", uk: "Сповіщення", fr: "Notifications")),
                FeatureItem(id: "islandPower", key: \.islandPower, title: Phrase("Charger and battery", ru: "Зарядка и батарея", uk: "Заряджання й батарея", fr: "Charge et batterie")),
                FeatureItem(id: "islandDevices", key: \.islandDevices, title: Phrase("Headphones and devices", ru: "Наушники и устройства", uk: "Навушники й пристрої", fr: "Écouteurs et appareils")),
                FeatureItem(id: "islandVolume", key: \.islandVolume, title: Phrase("Volume", ru: "Громкость", uk: "Гучність", fr: "Volume"),
                            detail: Phrase("Shows the level when it changes", ru: "Показывает уровень, когда он меняется",
                                           uk: "Показує рівень, коли він змінюється", fr: "Affiche le niveau quand il change")),
                FeatureItem(id: "islandHaptics", key: \.islandHaptics, title: Phrase("Haptic feedback", ru: "Тактильный отклик", uk: "Тактильний відгук", fr: "Retour haptique"))
            ]),
        FeatureGroup(
            id: "sound", symbol: "speaker.wave.3.fill", title: Phrase("Sound", ru: "Звук", uk: "Звук", fr: "Son"),
            detail: Phrase("A volume, an output and a ceiling for every app.", ru: "Своя громкость, выход и потолок у каждого приложения.",
                           uk: "Своя гучність, вихід і стеля в кожного застосунку.", fr: "Un volume, une sortie et un plafond par app."),
            main: FeatureItem(id: "mixer", key: \.mixer, title: Phrase("Per-app volume", ru: "Громкость приложений", uk: "Гучність застосунків", fr: "Volume par app")),
            options: [
                FeatureItem(id: "outputHotkey", key: \.outputHotkey, title: Phrase("Next output", ru: "Следующий выход", uk: "Наступний вихід", fr: "Sortie suivante"), keys: ["⌃", "⌥", "O"]),
                FeatureItem(id: "micHotkey", key: \.micHotkey, title: Phrase("Mute all mics", ru: "Заглушить микрофоны", uk: "Заглушити мікрофони", fr: "Couper les micros"), keys: ["⌃", "⌥", "M"]),
                FeatureItem(id: "headphoneGuard", key: \.headphoneGuard, title: Phrase("Headphone guard", ru: "Защита при снятии наушников", uk: "Захист при знятті навушників", fr: "Garde écouteurs"),
                            detail: Phrase("Lowers the volume before speakers take over", ru: "Убавляет звук, прежде чем заиграют колонки", uk: "Зменшує звук, перш ніж заграють колонки", fr: "Baisse le volume avant les haut-parleurs"))
            ]),
        FeatureGroup(
            id: "windows", symbol: "macwindow.on.rectangle", title: Phrase("Windows and Dock", ru: "Окна и Dock", uk: "Вікна й Dock", fr: "Fenêtres et Dock"),
            detail: Phrase("Switch, snap and preview windows.", ru: "Переключение, раскладка и превью окон.", uk: "Перемикання, розкладка й превʼю вікон.", fr: "Changer, ranger et prévisualiser les fenêtres."),
            main: FeatureItem(id: "switcher", key: \.switcher, title: Phrase("Window switcher", ru: "Переключатель окон", uk: "Перемикач вікон", fr: "Sélecteur de fenêtres"), keys: ["⌥", "Tab"]),
            options: [
                FeatureItem(id: "switcherPreviews", key: \.switcherPreviews, title: Phrase("Live previews", ru: "Живые превью", uk: "Живі превʼю", fr: "Aperçus en direct")),
                FeatureItem(id: "switcherCommandTab", key: \.switcherCommandTab, title: Phrase("Replace ⌘Tab", ru: "Заменить ⌘Tab", uk: "Замінити ⌘Tab", fr: "Remplacer ⌘Tab")),
                FeatureItem(id: "snapping", key: \.snapping, title: Phrase("Snap shortcuts", ru: "Раскладка клавишами", uk: "Розкладка клавішами", fr: "Raccourcis de placement"), keys: ["⌃", "⌥", "←"]),
                FeatureItem(id: "modifierDrag", key: \.modifierDrag, title: Phrase("Move and resize with ⌃⌘", ru: "Двигать и тянуть с ⌃⌘", uk: "Рухати й тягнути з ⌃⌘", fr: "Déplacer et redimensionner avec ⌃⌘")),
                FeatureItem(id: "edgeSnap", key: \.edgeSnap, title: Phrase("Snap at screen edges", ru: "Прилипание к краям", uk: "Прилипання до країв", fr: "Aimanter aux bords")),
                FeatureItem(id: "dockPreview", key: \.dockPreview, title: Phrase("Dock previews", ru: "Превью в Dock", uk: "Превʼю в Dock", fr: "Aperçus du Dock")),
                FeatureItem(id: "greenButton", key: \.greenButton, title: Phrase("Green button fills the screen", ru: "Зелёная кнопка — на весь экран", uk: "Зелена кнопка — на весь екран", fr: "Le bouton vert remplit l’écran")),
                FeatureItem(id: "quitGuard", key: \.quitGuard, title: Phrase("Hold ⌘Q to quit", ru: "Удерживать ⌘Q для выхода", uk: "Утримувати ⌘Q для виходу", fr: "Maintenir ⌘Q pour quitter")),
                FeatureItem(id: "quitOnClose", key: \.quitOnClose, title: Phrase("Quit when the last window closes", ru: "Выходить при закрытии последнего окна", uk: "Виходити при закритті останнього вікна", fr: "Quitter à la fermeture de la dernière fenêtre"))
            ],
            needs: .accessibility),
        FeatureGroup(
            id: "clipboard", symbol: "doc.on.clipboard.fill", title: Phrase("Clipboard and files", ru: "Буфер и файлы", uk: "Буфер і файли", fr: "Presse-papiers et fichiers"),
            detail: Phrase("History, the Shelf and Finder shortcuts.", ru: "История, полка и приёмы Finder.", uk: "Історія, полиця й прийоми Finder.", fr: "Historique, étagère et raccourcis du Finder."),
            main: FeatureItem(id: "clipboard", key: \.clipboard, title: Phrase("Clipboard history", ru: "История буфера", uk: "Історія буфера", fr: "Historique du presse-papiers"), keys: ["⌃", "⌥", "V"]),
            options: [
                FeatureItem(id: "plainPaste", key: \.plainPaste, title: Phrase("Paste as plain text", ru: "Вставка без форматирования", uk: "Вставлення без форматування", fr: "Coller en texte brut"), keys: ["⇧", "⌃", "⌥", "V"]),
                FeatureItem(id: "shelf", key: \.shelf, title: Phrase("Shelf", ru: "Полка", uk: "Полиця", fr: "Étagère")),
                FeatureItem(id: "shelfShake", key: \.shelfShake, title: Phrase("Shake to open the Shelf", ru: "Встряхнуть — открыть полку", uk: "Струснути — відкрити полицю", fr: "Secouer pour ouvrir l’étagère")),
                FeatureItem(id: "finderCut", key: \.finderCut, title: Phrase("Cut and paste in Finder", ru: "Вырезать и вставить в Finder", uk: "Вирізати й вставити у Finder", fr: "Couper-coller dans le Finder")),
                FeatureItem(id: "finderRename", key: \.finderRename, title: Phrase("F2 renames in Finder", ru: "F2 — переименовать в Finder", uk: "F2 — перейменувати у Finder", fr: "F2 renomme dans le Finder")),
                FeatureItem(id: "finderImages", key: \.finderImages, title: Phrase("Paste images as files", ru: "Вставлять картинки файлами", uk: "Вставляти зображення файлами", fr: "Coller les images en fichiers")),
                FeatureItem(id: "dmgInstaller", key: \.dmgInstaller, title: Phrase("Install apps from disk images", ru: "Ставить программы из образов", uk: "Ставити програми з образів", fr: "Installer depuis les images disque")),
                FeatureItem(id: "dmgTrash", key: \.dmgTrash, title: Phrase("Move used disk images to the Trash", ru: "Убирать образы в корзину", uk: "Прибирати образи в кошик", fr: "Mettre les images disque à la corbeille"))
            ],
            needs: .accessibility),
        FeatureGroup(
            id: "commands", symbol: "command", title: Phrase("Commands", ru: "Команды", uk: "Команди", fr: "Commandes"),
            detail: Phrase("Search, math and your favorite actions.", ru: "Поиск, расчёты и любимые действия.", uk: "Пошук, обчислення й улюблені дії.", fr: "Recherche, calculs et actions favorites."),
            main: FeatureItem(id: "commandBar", key: \.commandBar, title: Phrase("Command bar", ru: "Командная строка", uk: "Командний рядок", fr: "Barre de commandes"), keys: ["⌥", "Space"]),
            options: [
                FeatureItem(id: "radial", key: \.radial, title: Phrase("Radial menu", ru: "Круговое меню", uk: "Кругове меню", fr: "Menu radial"), keys: ["⌃", "⌥", "R"]),
                FeatureItem(id: "radialMouse", key: \.radialMouse, title: Phrase("Radial menu on the mouse", ru: "Круговое меню на мыши", uk: "Кругове меню на миші", fr: "Menu radial à la souris")),
                FeatureItem(id: "quickPanel", key: \.quickPanel, title: Phrase("Quick panel", ru: "Быстрая панель", uk: "Швидка панель", fr: "Panneau rapide"), keys: ["⌃", "⌥", "P"]),
                FeatureItem(id: "contextActions", key: \.contextActions,
                            title: Phrase("Actions on the selection", ru: "Действия с выделенным", uk: "Дії з виділеним", fr: "Actions sur la sélection"),
                            detail: Phrase("Text, links, images and files: OCR, convert, ZIP, QR, AI", ru: "Текст, ссылки, картинки и файлы: OCR, конвертация, ZIP, QR, ИИ",
                                           uk: "Текст, посилання, зображення й файли: OCR, конвертація, ZIP, QR, ШІ", fr: "Texte, liens, images et fichiers : OCR, conversion, ZIP, QR, IA"),
                            keys: ["⌃", "⌥", "A"]),
                FeatureItem(id: "automations", key: \.automations,
                            title: Phrase("Automations", ru: "Автоматизации", uk: "Автоматизації", fr: "Automatisations"),
                            detail: Phrase("When → if → do: devices, folders, apps, agents, battery", ru: "Когда → если → сделать: устройства, папки, приложения, агенты, батарея",
                                           uk: "Коли → якщо → зробити: пристрої, теки, застосунки, агенти, батарея", fr: "Quand → si → faire : appareils, dossiers, apps, agents, batterie"))
            ],
            needs: .accessibility),
        FeatureGroup(
            id: "agents", symbol: "sparkles", title: Phrase("AI agents", ru: "ИИ-агенты", uk: "ШІ-агенти", fr: "Agents IA"),
            detail: Phrase("What your coding agents are doing, and when they finish.", ru: "Чем заняты ваши агенты и когда они закончат.",
                           uk: "Чим зайняті ваші агенти й коли вони закінчать.", fr: "Ce que font vos agents et quand ils terminent."),
            main: FeatureItem(id: "agentsTab", key: \.islandAgents, title: Phrase("Agents in the island", ru: "Агенты в островке", uk: "Агенти в острівці", fr: "Agents dans l’îlot")),
            options: [
                FeatureItem(id: "agentChime", key: \.agentChime, title: Phrase("Sound when a task finishes", ru: "Звук по окончании задачи", uk: "Звук по завершенні завдання", fr: "Son à la fin d’une tâche"))
            ])
    ]
}

/// How many features are running, for the panel subtitle.
struct FeatureTally {
    var on: Int
    var total: Int

    /// A switch that sits in two groups ("Agents in the island") counts once, and runs if either place runs it.
    @MainActor init(_ settings: SuiteSettings) {
        var running: [ReferenceWritableKeyPath<SuiteSettings, Bool>: Bool] = [:]
        for group in FeatureGroup.all {
            let mainOn = settings[keyPath: group.main.key]
            running[group.main.key] = running[group.main.key] == true || mainOn
            for option in group.options {
                running[option.key] = running[option.key] == true || (mainOn && settings[keyPath: option.key])
            }
        }
        on = running.values.filter { $0 }.count
        total = running.count
    }
}

// MARK: Views

struct FeaturesPane: View {
    var model: AppModel
    let suite: Suite
    @State private var query = ""
    @State private var open: Set<String> = []

    var body: some View {
        let groups = filtered
        VStack(spacing: 12) {
            Overview(model: model, suite: suite)
            GlassField(prompt: FeaturePhrases.search.text, text: $query)
            if groups.isEmpty {
                Footnote(FeaturePhrases.nothing.text)
                    .padding(.horizontal, 4)
            }
            ForEach(groups, id: \.group.id) { entry in
                GroupCard(model: model, settings: suite.settings, group: entry.group, items: entry.items,
                          expanded: !query.isEmpty || open.contains(entry.group.id)) {
                    withAnimation(.panelSpring) {
                        if open.contains(entry.group.id) { open.remove(entry.group.id) } else { open.insert(entry.group.id) }
                    }
                }
            }
        }
    }

    /// Searching matches a group's title or any of its switches, and shows only the matches.
    private var filtered: [(group: FeatureGroup, items: [FeatureItem])] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        return FeatureGroup.all.compactMap { group in
            guard !needle.isEmpty else { return (group, group.options) }
            let matches = group.options.filter { $0.title.text.lowercased().contains(needle) || ($0.detail?.text.lowercased().contains(needle) ?? false) }
            let groupHit = group.title.text.lowercased().contains(needle) || group.main.title.text.lowercased().contains(needle)
            if groupHit { return (group, group.options) }
            return matches.isEmpty ? nil : (group, matches)
        }
    }
}

private struct Overview: View {
    var model: AppModel
    let suite: Suite

    var body: some View {
        let tally = FeatureTally(suite.settings)
        let permissions = model.permissions
        let needsAccess = !permissions.accessibilityGranted && FeatureGroup.all.contains { $0.needs == .accessibility && suite.settings[keyPath: $0.main.key] }
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().stroke(Color.white.opacity(0.1), lineWidth: 5)
                    Circle().trim(from: 0, to: tally.total > 0 ? CGFloat(tally.on) / CGFloat(tally.total) : 0)
                        .stroke(Palette.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text(model.integer(tally.on))
                        .font(.system(size: 15, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(Palette.ink)
                }
                .frame(width: 50, height: 50)
                .animation(.panelSpring, value: tally.on)
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.format(.featuresSubtitle, model.integer(tally.on), model.integer(tally.total)))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                    Text(FeaturePhrases.overview.text)
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if needsAccess {
                PermissionCallout(symbol: "hand.raised.fill", title: model.text(.permAccessibility), message: FeaturePhrases.needsAccess.text,
                                  actions: [CalloutAction(title: model.text(.allow), prominent: true) { model.permissions.requestAccessibility() }])
            }
        }
        .card(padding: 18)
    }
}

private struct GroupCard: View {
    var model: AppModel
    @Bindable var settings: SuiteSettings
    let group: FeatureGroup
    let items: [FeatureItem]
    let expanded: Bool
    let toggle: () -> Void

    var body: some View {
        let on = settings[keyPath: group.main.key]
        let tally = group.tally(settings)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                RowIcon(symbol: group.symbol, tint: on ? Palette.accent : Palette.secondary, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(group.title.text).font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.ink)
                        if group.needs == .accessibility && on && !model.permissions.accessibilityGranted {
                            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 10, weight: .bold)).foregroundStyle(Palette.warning)
                                .help(FeaturePhrases.needsAccess.text)
                        }
                    }
                    Text(on ? FeaturePhrases.count(model.integer(tally.on), model.integer(tally.total)) : group.detail.text)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                if !group.main.keys.isEmpty { KeyCaps(keys: group.main.keys, size: 18).opacity(on ? 1 : 0.5) }
                GlassSwitch(isOn: on) { settings[keyPath: group.main.key].toggle() }
                    .accessibilityLabel(group.main.title.text)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: toggle)
            if expanded {
                VStack(spacing: 0) {
                    Hairline().padding(.vertical, 8)
                    if group.main.title.text != group.title.text {
                        OptionRow(item: group.main, settings: settings, enabled: true)
                        Hairline(inset: 0)
                    }
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        OptionRow(item: item, settings: settings, enabled: on)
                        if index < items.count - 1 { Hairline(inset: 0) }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            Button(action: toggle) {
                HStack(spacing: 4) {
                    Text(expanded ? FeaturePhrases.less.text : FeaturePhrases.options(model.integer(items.count)))
                    Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.system(size: 9, weight: .bold))
                }
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Palette.accent)
                .padding(.top, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .card()
    }
}

private struct OptionRow: View {
    let item: FeatureItem
    @Bindable var settings: SuiteSettings
    let enabled: Bool

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title.text).font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.ink)
                if let detail = item.detail {
                    Text(detail.text).font(.system(size: 11)).foregroundStyle(Palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            if !item.keys.isEmpty { KeyCaps(keys: item.keys, size: 18) }
            GlassSwitch(isOn: settings[keyPath: item.key]) { settings[keyPath: item.key].toggle() }
                .accessibilityLabel(item.title.text)
        }
        .padding(.vertical, 7)
        .opacity(enabled ? 1 : 0.4)
        .disabled(!enabled)
    }
}

enum FeaturePhrases {
    static let search = Phrase("Find a feature", ru: "Найти функцию", uk: "Знайти функцію", fr: "Trouver une fonction")
    static let nothing = Phrase("Nothing matches. Try another word.", ru: "Ничего не нашлось. Попробуйте другое слово.",
                                uk: "Нічого не знайдено. Спробуйте інше слово.", fr: "Aucun résultat. Essayez un autre mot.")
    static let overview = Phrase("Everything SAVISUL adds to macOS, with a switch each. Options run only while their group is on.",
                                 ru: "Всё, что SAVISUL добавляет в macOS, у каждого — свой переключатель. Опции работают, пока включена их группа.",
                                 uk: "Усе, що SAVISUL додає в macOS, у кожного — свій перемикач. Опції працюють, поки ввімкнено їхню групу.",
                                 fr: "Tout ce que SAVISUL ajoute à macOS, chacun avec son interrupteur. Les options ne tournent que si leur groupe est actif.")
    static let needsAccess = Phrase("Windows, clipboard and command features need Accessibility to work.",
                                    ru: "Окнам, буферу и командам нужен Универсальный доступ.",
                                    uk: "Вікнам, буферу й командам потрібен Універсальний доступ.",
                                    fr: "Les fenêtres, le presse-papiers et les commandes ont besoin de l’Accessibilité.")
    static let less = Phrase("Hide options", ru: "Скрыть опции", uk: "Сховати опції", fr: "Masquer les options")

    @MainActor static func options(_ count: String) -> String {
        Phrase("Options · %@", ru: "Опции · %@", uk: "Опції · %@", fr: "Options · %@")(count)
    }
    @MainActor static func count(_ on: String, _ total: String) -> String {
        Phrase("%@ of %@ on", ru: "Включено %@ из %@", uk: "Увімкнено %@ з %@", fr: "%@ sur %@ actifs")(on, total)
    }
}
