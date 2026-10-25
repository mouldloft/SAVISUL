import AppKit
import SwiftUI

/// What one release changed, as the "What's new" screen tells it.
struct ReleaseNote: Identifiable {
    struct Item: Identifiable {
        let symbol: String
        let tint: Color
        let title: Phrase
        let detail: Phrase
        var action: Action?
        /// About the assistant, which only builds with Mould Engine have.
        var engine = false

        var id: String { symbol + title.en }
    }

    /// Where an item's button takes the person.
    enum Action {
        case assistant, features, updates, downloadModel, downloadPhotoModel

        var title: Phrase {
            switch self {
            case .downloadModel: Phrase("Download the model", ru: "Скачать модель", uk: "Завантажити модель", fr: "Télécharger le modèle")
            case .downloadPhotoModel: Phrase("Download (138 MB)", ru: "Скачать (138 МБ)", uk: "Завантажити (138 МБ)", fr: "Télécharger (138 Mo)")
            case .assistant: Phrase("Try it", ru: "Попробовать", uk: "Спробувати", fr: "Essayer")
            case .features: Phrase("Open Features", ru: "Открыть «Функции»", uk: "Відкрити «Функції»", fr: "Ouvrir les Fonctions")
            case .updates: Phrase("Open Settings", ru: "Открыть настройки", uk: "Відкрити налаштування", fr: "Ouvrir les Réglages")
            }
        }
    }

    let version: String
    let items: [Item]

    var id: String { version }
}

enum ReleaseNotes {
    /// Newest first. Each release adds its own at the top.
    static let all: [ReleaseNote] = [
        ReleaseNote(version: "2.9.2", items: [
            .init(symbol: "sparkle.magnifyingglass", tint: Palette.accent,
                  title: Phrase("Photos found by what they show", ru: "Фото ищутся по смыслу", uk: "Фото шукаються за змістом", fr: "Les photos trouvées par ce qu’elles montrent"),
                  detail: Phrase("The assistant now understands what a picture shows, not just Vision’s labels: the cat on the sofa, the receipt from the café, the screenshot with the error. When nothing matches, it says so instead of showing something else, and offers a few close ones only as maybes. Search by meaning is CLIP, 138 MB, downloaded once; it runs on this Mac and sends nothing.",
                                 ru: "Ассистент теперь понимает, что на снимке, а не только метки Apple Vision: кот на диване, чек из кафе, скриншот с ошибкой. Если ничего не подходит, он так и скажет, а не покажет другое, и лишь предложит пару похожих как «возможно». Поиск по смыслу — это модель CLIP, 138 МБ, скачивается один раз, работает на этом Mac и ничего не отправляет.",
                                 uk: "Асистент тепер розуміє, що на знімку, а не лише мітки Apple Vision: кіт на дивані, чек із кафе, скриншот із помилкою. Якщо нічого не підходить, він так і скаже, а не покаже інше, і лише запропонує кілька схожих як «можливо». Пошук за змістом — це модель CLIP, 138 МБ, завантажується один раз, працює на цьому Mac і нічого не надсилає.",
                                 fr: "L’assistant comprend maintenant ce que montre une image, pas seulement les étiquettes de Vision : le chat sur le canapé, le ticket du café, la capture avec l’erreur. Quand rien ne correspond, il le dit au lieu de montrer autre chose, et ne propose que quelques images proches, comme des peut-être. La recherche par le sens, c’est CLIP : 138 Mo téléchargés une fois, sur ce Mac, sans rien envoyer."),
                  action: .downloadPhotoModel, engine: true)
        ]),
        ReleaseNote(version: "2.9.1", items: [
            .init(symbol: "key.fill", tint: Palette.accent,
                  title: Phrase("Your own AI runs the assistant", ru: "Ваш ИИ — мозг ассистента", uk: "Ваш ШІ — мозок асистента", fr: "Votre IA pilote l’assistant"),
                  detail: Phrase("Connected a key in Settings → AI? The assistant now thinks with that model (DeepSeek, Claude, GPT, Gemini…), so it understands and finds far better. Models on this Mac step in without internet, if the key stops working, or when you choose Only on this Mac. What you select stays on this Mac unless you allow it.",
                                 ru: "Подключили ключ в Настройки → ИИ? Теперь ассистент думает этой моделью — DeepSeek, Claude, GPT, Gemini и другими, — поэтому понимает и находит намного лучше. Модели на этом Mac выручат без интернета, если ключ перестанет работать или если выбрать «Только на этом Mac». Выделенное вами не покидает Mac без вашего разрешения.",
                                 uk: "Підключили ключ у Налаштування → ШІ? Тепер асистент думає цією моделлю — DeepSeek, Claude, GPT, Gemini та іншими, — тому розуміє й знаходить набагато краще. Моделі на цьому Mac виручать без інтернету, якщо ключ перестане працювати або якщо вибрати «Лише на цьому Mac». Виділене вами не залишає Mac без вашого дозволу.",
                                 fr: "Une clé dans Réglages → IA ? L’assistant réfléchit maintenant avec ce modèle (DeepSeek, Claude, GPT, Gemini…) : il comprend et trouve bien mieux. Les modèles de ce Mac prennent le relais sans internet, si la clé ne marche plus, ou si vous choisissez Uniquement sur ce Mac. Ce que vous sélectionnez reste sur ce Mac sauf si vous l’autorisez."),
                  action: .assistant, engine: true),
            .init(symbol: "photo.on.rectangle.angled", tint: Palette.positive,
                  title: Phrase("Photos, the moment you ask", ru: "«Фото» — как только спросите", uk: "«Фото» — щойно запитаєте", fr: "Photos, dès que vous demandez"),
                  detail: Phrase("Ask for a photo and SAVISUL asks macOS for your Photos library right then, so the search covers it. Found nothing in your folders? It says where else to look.",
                                 ru: "Попросите найти фото — и SAVISUL сразу попросит у macOS доступ к медиатеке «Фото», чтобы искать и в ней. Ничего не нашлось в папках? Ассистент подскажет, где ещё поискать.",
                                 uk: "Попросіть знайти фото — і SAVISUL одразу попросить у macOS доступ до медіатеки «Фото», щоб шукати й у ній. Нічого не знайшлося в теках? Асистент підкаже, де ще пошукати.",
                                 fr: "Demandez une photo et SAVISUL demande aussitôt à macOS l’accès à votre Photothèque, pour y chercher aussi. Rien dans vos dossiers ? Il dit où chercher encore."),
                  engine: true)
        ]),
        ReleaseNote(version: "2.9", items: [
            .init(symbol: "sparkles", tint: Palette.accent,
                  title: Phrase("The assistant understands at once", ru: "Ассистент понимает с полуслова", uk: "Асистент розуміє з півслова",
                                fr: "L’assistant comprend tout de suite"),
                  detail: Phrase("Everyday requests run straight away and the same every time: check the Mac, sort Downloads, your meetings, your AI agents, a photo, a feature on or off. For the rest, the model on this Mac gets only the tools the request needs, so it answers faster and no longer goes in circles.",
                                 ru: "Частые просьбы выполняются сразу и всегда одинаково: проверить Mac, разобрать «Загрузки», встречи, ИИ-агенты, найти фото, включить или выключить функцию. Для остального модель на этом Mac получает только нужные запросу инструменты, поэтому отвечает быстрее и больше не ходит по кругу.",
                                 uk: "Часті прохання виконуються одразу й завжди однаково: перевірити Mac, розібрати «Завантаження», зустрічі, ШІ-агенти, знайти фото, увімкнути чи вимкнути функцію. Для решти модель на цьому Mac отримує лише потрібні запиту інструменти, тому відповідає швидше й більше не ходить по колу.",
                                 fr: "Les demandes courantes s’exécutent tout de suite, et toujours de la même façon : vérifier le Mac, trier les Téléchargements, vos réunions, vos agents IA, une photo, une fonction à activer ou couper. Pour le reste, le modèle de ce Mac ne reçoit que les outils utiles à la demande : il répond plus vite et ne tourne plus en rond."),
                  action: .assistant, engine: true),
            .init(symbol: "cpu", tint: Palette.positive,
                  title: Phrase("A smarter model, still on this Mac", ru: "Модель умнее — по-прежнему на этом Mac", uk: "Розумніша модель — як і раніше, на цьому Mac",
                                fr: "Un modèle plus malin, toujours sur ce Mac"),
                  detail: Phrase("Qwen3 4B understands far better than the model before it, Ukrainian and Russian included, and stays just as private: it runs here. 2.5 GB, downloaded once; the assistant uses it as soon as it is there, and the smaller one steps in when memory is short.",
                                 ru: "Qwen3 4B понимает намного лучше прежней модели, в том числе по-украински и по-русски, и так же приватна: работает здесь. 2,5 ГБ, скачивается один раз; ассистент начнёт ею пользоваться сразу, а прежняя выручит, когда мало памяти.",
                                 uk: "Qwen3 4B розуміє набагато краще за попередню модель, зокрема українською та російською, і так само приватна: працює тут. 2,5 ГБ, завантажується один раз; асистент почне нею користуватися одразу, а попередня виручить, коли мало памʼяті.",
                                 fr: "Qwen3 4B comprend bien mieux que le modèle d’avant, ukrainien et russe compris, et reste aussi privé : il tourne ici. 2,5 Go, téléchargés une fois ; l’assistant s’en sert dès qu’il est là, et le plus petit prend le relais quand la mémoire manque."),
                  action: .downloadModel, engine: true),
            .init(symbol: "gift.fill", tint: Palette.positive,
                  title: Phrase("What’s new, after every update", ru: "Что нового — после каждого обновления", uk: "Що нового — після кожного оновлення",
                                fr: "Les nouveautés, après chaque mise à jour"),
                  detail: Phrase("This screen. After each update SAVISUL says what changed; Settings → Updates shows it again whenever you like.",
                                 ru: "Этот экран. После каждого обновления SAVISUL расскажет, что изменилось, а в Настройки → Обновления его можно открыть снова в любой момент.",
                                 uk: "Цей екран. Після кожного оновлення SAVISUL розповість, що змінилося, а в Налаштування → Оновлення його можна відкрити знову будь-коли.",
                                 fr: "Cet écran. Après chaque mise à jour, SAVISUL dit ce qui a changé ; Réglages → Mises à jour le rouvre quand vous voulez."))
        ]),
        ReleaseNote(version: "2.8", items: [
            .init(symbol: "photo.on.rectangle.angled", tint: Palette.accent,
                  title: Phrase("Find a photo by what is in it", ru: "Поиск фото по описанию", uk: "Пошук фото за описом", fr: "Retrouver une photo d’après ce qu’elle montre"),
                  detail: Phrase("Ask the assistant “Find the photo of a cat on the sofa”. Pictures in Photos and in its folders are recognized on this Mac with Apple’s Vision; nothing is sent anywhere.",
                                 ru: "Спросите ассистента: «Найди фото кота на диване». Картинки из «Фото» и из его папок разбираются прямо на этом Mac с помощью Apple Vision, никуда ничего не отправляется.",
                                 uk: "Запитайте асистента: «Знайди фото кота на дивані». Зображення з «Фото» та з його тек розбираються просто на цьому Mac за допомогою Apple Vision, нікуди нічого не надсилається.",
                                 fr: "Demandez à l’assistant « Trouve la photo du chat sur le canapé ». Les images de Photos et de ses dossiers sont analysées sur ce Mac avec Vision d’Apple ; rien n’est envoyé."),
                  action: .assistant, engine: true),
            .init(symbol: "pawprint.fill", tint: Palette.warning,
                  title: Phrase("The panda has a switch of its own", ru: "У панды свой переключатель", uk: "У панди свій перемикач", fr: "Le panda a son propre interrupteur"),
                  detail: Phrase("Features → Panda: turn it off if it gets in the way, its sounds too.",
                                 ru: "«Функции» → «Панда»: выключите, если она мешает, вместе со звуками.",
                                 uk: "«Функції» → «Панда»: вимкніть, якщо вона заважає, разом зі звуками.",
                                 fr: "Fonctions → Panda : coupez-le s’il gêne, ses sons aussi."),
                  action: .features),
            .init(symbol: "checkmark.seal.fill", tint: Palette.positive,
                  title: Phrase("Updates checked by Apple", ru: "Обновления, проверенные Apple", uk: "Оновлення, перевірені Apple", fr: "Des mises à jour vérifiées par Apple"),
                  detail: Phrase("SAVISUL from savisul.com updates only to builds signed with Mould Loft’s Developer ID and notarized by Apple.",
                                 ru: "SAVISUL с savisul.com обновляется только сборками с Developer ID Mould Loft, которые проверила Apple.",
                                 uk: "SAVISUL із savisul.com оновлюється лише збірками з Developer ID Mould Loft, які перевірила Apple.",
                                 fr: "Le SAVISUL de savisul.com ne se met à jour qu’avec des versions signées par le Developer ID de Mould Loft et notariées par Apple."))
        ])
    ]

    /// The releases after `seen` up to `current`, newest first and at most three; with nothing seen, this version and the
    /// one before it.
    static func since(_ seen: String?, current: String, in notes: [ReleaseNote] = all) -> [ReleaseNote] {
        #if MOULD_ENGINE
        let shown = notes
        #else
        let shown = notes.map { ReleaseNote(version: $0.version, items: $0.items.filter { !$0.engine }) }.filter { !$0.items.isEmpty }
        #endif
        let upTo = shown.filter { !Updater.isNewer($0.version, than: current) }
        guard let seen else { return Array(upTo.prefix(2)) }
        return Array(upTo.filter { Updater.isNewer($0.version, than: seen) }.prefix(3))
    }
}

/// After an update, SAVISUL says what changed: once, on the first launch of the new version, a little after it starts.
/// Settings → Updates opens the same screen again.
@MainActor
final class WhatsNew: NSObject, NSWindowDelegate {
    static let shared = WhatsNew()

    /// Whether SAVISUL ran on this Mac before this launch, read before anything writes its settings: a first launch
    /// after installing has nothing new to tell.
    private static var ranBefore = false
    private var window: NSWindow?

    static func noteLaunch(_ defaults: UserDefaults = SettingsDefaults.store) {
        ranBefore = defaults.object(forKey: "suite.settingsVersion") != nil
    }

    /// The notes to show at this launch, if any, remembering this version as seen.
    static func due(current: String, defaults: UserDefaults = SettingsDefaults.store, ranBefore given: Bool? = nil) -> [ReleaseNote] {
        let ranBefore = given ?? Self.ranBefore
        let seen = defaults.string(forKey: "whatsNew.seen")
        defaults.set(current, forKey: "whatsNew.seen")
        if let seen {
            return Updater.isNewer(current, than: seen) ? ReleaseNotes.since(seen, current: current) : []
        }
        // Updated from a version that didn't keep this yet, or a first launch.
        return ranBefore ? ReleaseNotes.since(nil, current: current) : []
    }

    func launched() {
        let notes = Self.due(current: Updater.shared.current)
        guard !notes.isEmpty else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            MainActor.assumeIsolated { WhatsNew.shared.show(notes) }
        }
    }

    func show(_ notes: [ReleaseNote]? = nil) {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        let notes = notes ?? ReleaseNotes.since(nil, current: Updater.shared.current)
        guard !notes.isEmpty else { return }
        let size = NSSize(width: 540, height: 660)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.title = WhatsNewPhrases.title(notes[0].version)
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
        window.appearance = NSAppearance(named: .darkAqua)
        let glass = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        glass.material = .hudWindow
        glass.blendingMode = .behindWindow
        glass.state = .active
        let hosting = NSHostingView(rootView: WhatsNewView(notes: notes) { [weak self] in self?.window?.close() }.environment(\.colorScheme, .dark))
        hosting.frame = glass.bounds
        hosting.autoresizingMask = [.width, .height]
        glass.addSubview(hosting)
        window.contentView = glass
        window.center()
        window.delegate = self
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }

    /// Whether search by meaning is already here, so its download button can stay away.
    static var photoModelInstalled: Bool {
        #if MOULD_ENGINE
        PhotoModel.installed
        #else
        true
        #endif
    }

    /// Whether the recommended local model is already here, so its download button can stay away.
    static var modelInstalled: Bool {
        #if MOULD_ENGINE
        LocalModels.installed().contains { $0.id == LocalModels.recommendedID }
        #else
        true
        #endif
    }

    fileprivate static func perform(_ action: ReleaseNote.Action) {
        switch action {
        case .downloadModel:
            #if MOULD_ENGINE
            if !Suite.shared.settings.assistant { Suite.shared.settings.assistant = true }
            MindHost.shared.downloadRecommended()
            #endif
            Suite.shared.app?.select(.features)
            Suite.shared.app?.onShow?()
        case .downloadPhotoModel:
            #if MOULD_ENGINE
            if !Suite.shared.settings.assistant { Suite.shared.settings.assistant = true }
            PhotoSearch.shared.installModel()
            #endif
            // Settings → Assistant shows it coming.
            Suite.shared.app?.select(.settings)
            Suite.shared.app?.onShow?()
        case .assistant:
            #if MOULD_ENGINE
            if !Suite.shared.settings.assistant { Suite.shared.settings.assistant = true }
            MindPanel.shared.open()
            #else
            Suite.shared.app?.select(.features)
            Suite.shared.app?.onShow?()
            #endif
        case .features:
            Suite.shared.app?.select(.features)
            Suite.shared.app?.onShow?()
        case .updates:
            Suite.shared.app?.select(.settings)
            Suite.shared.app?.onShow?()
        }
    }
}

struct WhatsNewView: View {
    let notes: [ReleaseNote]
    let close: () -> Void
    @State private var shown = false
    private let still = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header.padding(.bottom, 6)
                    ForEach(Array(notes.enumerated()), id: \.element.id) { index, note in
                        if index > 0 {
                            Text(WhatsNewPhrases.inVersion(note.version)).font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.tertiary)
                                .textCase(.uppercase).tracking(0.6).padding(.top, 10)
                        }
                        ForEach(Array(note.items.enumerated()), id: \.element.id) { itemIndex, item in
                            WhatsNewCard(item: item, close: close)
                                .opacity(shown ? 1 : 0)
                                .offset(y: shown || still ? 0 : 14)
                                .animation(still ? nil : .spring(response: 0.55, dampingFraction: 0.86).delay(0.12 + 0.07 * Double(order(index, itemIndex))),
                                           value: shown)
                        }
                    }
                }
                .padding(.horizontal, 30)
                .padding(.top, 44)
                .padding(.bottom, 20)
            }
            Rectangle().fill(Palette.hairline).frame(height: 1)
            HStack {
                Spacer()
                PillButton(title: WhatsNewPhrases.done.text, prominent: true, action: close)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 30)
            .padding(.vertical, 16)
        }
        .onAppear { shown = true }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 58, height: 58)
                .scaleEffect(shown || still ? 1 : 0.8)
                .animation(still ? nil : .spring(response: 0.5, dampingFraction: 0.7), value: shown)
            VStack(alignment: .leading, spacing: 4) {
                Text(WhatsNewPhrases.title(notes[0].version)).font(.system(size: 24, weight: .bold)).foregroundStyle(Palette.ink)
                Text(WhatsNewPhrases.installed.text).font(.system(size: 13)).foregroundStyle(Palette.secondary)
            }
            Spacer(minLength: 8)
            if Suite.shared.settings.islandPanda {
                PandaView(mood: .hello, size: 44).frame(width: 44, height: 36)
            }
        }
    }

    /// The card's place in the whole list, for the stagger.
    private func order(_ note: Int, _ item: Int) -> Int {
        notes.prefix(note).reduce(0) { $0 + $1.items.count } + item
    }
}

private struct WhatsNewCard: View {
    let item: ReleaseNote.Item
    let close: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            RowIcon(symbol: item.symbol, tint: item.tint, size: 36)
            VStack(alignment: .leading, spacing: 5) {
                Text(item.title.text).font(.system(size: 14.5, weight: .semibold)).foregroundStyle(Palette.ink)
                Text(item.detail.text).font(.system(size: 12.5)).foregroundStyle(Palette.secondary).lineSpacing(1.5)
                    .fixedSize(horizontal: false, vertical: true)
                if let action = item.action, action != .downloadModel || !WhatsNew.modelInstalled, action != .downloadPhotoModel || !WhatsNew.photoModelInstalled {
                    PillButton(title: action.title.text, symbol: action == .downloadModel || action == .downloadPhotoModel ? "arrow.down.circle" : "arrow.right") {
                        close()
                        WhatsNew.perform(action)
                    }
                    .padding(.top, 4)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 0.6))
    }
}

enum WhatsNewPhrases {
    static let installed = Phrase("The update is installed. Here’s what changed.", ru: "Обновление установлено. Вот что изменилось.",
                                  uk: "Оновлення встановлено. Ось що змінилося.", fr: "La mise à jour est installée. Voici ce qui change.")
    static let done = Phrase("Continue", ru: "Продолжить", uk: "Продовжити", fr: "Continuer")
    static let open = Phrase("What’s new", ru: "Что нового", uk: "Що нового", fr: "Nouveautés")

    @MainActor static func title(_ version: String) -> String {
        Phrase("What’s new in SAVISUL %@", ru: "Что нового в SAVISUL %@", uk: "Що нового в SAVISUL %@", fr: "Nouveautés de SAVISUL %@")(version)
    }

    @MainActor static func inVersion(_ version: String) -> String {
        Phrase("In %@", ru: "В версии %@", uk: "У версії %@", fr: "Dans la %@")(version)
    }
}

/// Panel renders (--dump-panels): the screen as this version shows it after an update.
@MainActor
enum WhatsNewRender {
    static func dump(to folder: URL, completion: @escaping () -> Void) {
        let size = NSSize(width: 540, height: 660)
        let view = WhatsNewView(notes: ReleaseNotes.since(nil, current: Updater.shared.current), close: {})
            .frame(width: size.width, height: size.height)
            .background(Color(red: 0.11, green: 0.105, blue: 0.1))
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -4000, y: -4000), size: size), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: view.environment(\.colorScheme, .dark))
        window.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            MainActor.assumeIsolated {
                if let content = window.contentView, let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
                    content.cacheDisplay(in: content.bounds, to: bitmap)
                    try? bitmap.representation(using: .png, properties: [:])?.write(to: folder.appendingPathComponent("panels-whats-new.png"))
                }
                window.orderOut(nil)
                completion()
            }
        }
    }
}
