#if MOULD_ENGINE
import Foundation
import MouldEngine

enum MindPhrases {
    static let title = Phrase("Assistant", ru: "Ассистент", uk: "Асистент", fr: "Assistant")
    static let starting = Phrase("Starting…", ru: "Запускается…", uk: "Запускається…", fr: "Démarrage…")
    static let thinking = Phrase("Thinking…", ru: "Думаю…", uk: "Думаю…", fr: "Réflexion…")
    static let done = Phrase("Done", ru: "Готово", uk: "Готово", fr: "Terminé")
    static let stopped = Phrase("Stopped", ru: "Остановлено", uk: "Зупинено", fr: "Arrêté")
    static let onThisMac = Phrase("On this Mac", ru: "На этом Mac", uk: "На цьому Mac", fr: "Sur ce Mac")
    static let cloud = Phrase("Cloud", ru: "Облако", uk: "Хмара", fr: "Cloud")
    static let noModel = Phrase("No model to answer yet", ru: "Пока нет модели для ответов", uk: "Поки немає моделі для відповідей",
                                fr: "Pas encore de modèle pour répondre")
    static let noModelDetail = Phrase("Download the free local model in Settings → Features → Assistant, or add an API key in the AI settings.",
                                      ru: "Скачайте бесплатную локальную модель в Настройки → Функции → Ассистент или добавьте ключ API в настройках ИИ.",
                                      uk: "Завантажте безкоштовну локальну модель у Налаштування → Функції → Асистент або додайте ключ API в налаштуваннях ШІ.",
                                      fr: "Téléchargez le modèle local gratuit dans Réglages → Fonctions → Assistant, ou ajoutez une clé d’API dans les réglages IA.")
    static let installLlama = Phrase("Local models run with llama.cpp: install it with “brew install llama.cpp”. Or add an API key in the AI settings.",
                                     ru: "Локальные модели работают через llama.cpp: установите его командой «brew install llama.cpp». Или добавьте ключ API в настройках ИИ.",
                                     uk: "Локальні моделі працюють через llama.cpp: встановіть його командою «brew install llama.cpp». Або додайте ключ API в налаштуваннях ШІ.",
                                     fr: "Les modèles locaux tournent avec llama.cpp : installez-le avec « brew install llama.cpp ». Ou ajoutez une clé d’API dans les réglages IA.")
    static let undoLast = Phrase("Undo the last change", ru: "Отменить последнее изменение", uk: "Скасувати останню зміну", fr: "Annuler la dernière modification")
    static let undo = Phrase("Undo", ru: "Отменить", uk: "Скасувати", fr: "Annuler")
    static let nothingToUndo = Phrase("Nothing to undo", ru: "Отменять нечего", uk: "Скасовувати нічого", fr: "Rien à annuler")
    static let newChat = Phrase("New chat", ru: "Новый разговор", uk: "Нова розмова", fr: "Nouvelle discussion")
    static let thisPage = Phrase("This page", ru: "Эта страница", uk: "Ця сторінка", fr: "Cette page")
    static let noPage = Phrase("Couldn’t read the page’s address from the browser", ru: "Не удалось узнать адрес страницы в браузере",
                               uk: "Не вдалося дізнатися адресу сторінки в браузері", fr: "Impossible de lire l’adresse de la page dans le navigateur")
    static let selectedText = Phrase("Selected text", ru: "Выделенный текст", uk: "Виділений текст", fr: "Texte sélectionné")
    static let placeholder = Phrase("Ask, or say what to do…", ru: "Спросите или поручите…", uk: "Запитайте або доручіть…", fr: "Demandez, ou dites quoi faire…")
    static let stop = Phrase("Stop", ru: "Остановить", uk: "Зупинити", fr: "Arrêter")
    static let hello = Phrase("What can I do?", ru: "Чем помочь?", uk: "Чим допомогти?", fr: "Que puis-je faire ?")
    static let helloDetail = Phrase("I can check this Mac, find photos by what is in them, sort and find files, work with the text, files or page you bring, and set up automations. Anything that changes something is shown to you first and can be undone.",
                                    ru: "Могу проверить этот Mac, найти фото по тому, что на них, разобрать и найти файлы, поработать с выделенным текстом, файлами или страницей и настроить автоматизации. Всё, что что-то меняет, я сначала показываю, и это можно отменить.",
                                    uk: "Можу перевірити цей Mac, знайти фото за тим, що на них, розібрати й знайти файли, попрацювати з виділеним текстом, файлами чи сторінкою та налаштувати автоматизації. Усе, що щось змінює, я спершу показую, і це можна скасувати.",
                                    fr: "Je peux vérifier ce Mac, retrouver des photos d’après ce qu’elles montrent, trier et retrouver des fichiers, travailler sur le texte, les fichiers ou la page que vous apportez, et créer des automatisations. Tout ce qui modifie quelque chose vous est d’abord montré et peut être annulé.")
    static let capabilities = Phrase("""
        Hi! I’m SAVISUL’s assistant, and I work right on this Mac. For example:
        • “Check my Mac”: memory, processor, disk and battery
        • “Sort my Downloads”: files into folders, after showing you what goes where
        • “What meetings do I have today?” and “What are my agents doing?”
        • “Find the photo of a cat on the sofa”
        • “Turn off the panda”, or any other feature
        I can also translate, summarize or explain the text you select.
        """, ru: """
        Привет! Я ассистент SAVISUL и работаю прямо на этом Mac. Например:
        • «Проверь Mac» — память, процессор, диск и батарея
        • «Разбери Загрузки» — разложу файлы по папкам, сначала показав, что куда
        • «Какие у меня встречи сегодня?» и «Что делают агенты?»
        • «Найди фото кота на диване»
        • «Выключи панду» — или любую другую функцию
        А ещё могу перевести, пересказать или объяснить выделенный текст.
        """, uk: """
        Привіт! Я асистент SAVISUL і працюю просто на цьому Mac. Наприклад:
        • «Перевір Mac» — памʼять, процесор, диск і батарея
        • «Розбери Завантаження» — розкладу файли по теках, спершу показавши, що куди
        • «Які в мене зустрічі сьогодні?» і «Що роблять агенти?»
        • «Знайди фото кота на дивані»
        • «Вимкни панду» — або будь-яку іншу функцію
        А ще можу перекласти, переказати чи пояснити виділений текст.
        """, fr: """
        Bonjour ! Je suis l’assistant de SAVISUL et je travaille sur ce Mac. Par exemple :
        • « Vérifie mon Mac » : mémoire, processeur, disque et batterie
        • « Range mes Téléchargements » : les fichiers en dossiers, après vous avoir montré quoi va où
        • « Quelles réunions aujourd’hui ? » et « Que font mes agents ? »
        • « Trouve la photo du chat sur le canapé »
        • « Coupe le panda », ou toute autre fonction
        Je peux aussi traduire, résumer ou expliquer le texte sélectionné.
        """)
    static let noMeetings = Phrase("No meetings coming up.", ru: "Ближайших встреч нет.", uk: "Найближчих зустрічей немає.", fr: "Aucune réunion à venir.")
    static let noCalendar = Phrase("SAVISUL doesn’t see your calendar yet: turn on Next meeting in Features → Island and allow access.",
                                   ru: "SAVISUL пока не видит календарь: включите «Ближайшая встреча» в «Функции» → «Островок» и разрешите доступ.",
                                   uk: "SAVISUL поки не бачить календар: увімкніть «Найближча зустріч» у «Функції» → «Острівець» і дозвольте доступ.",
                                   fr: "SAVISUL ne voit pas encore votre agenda : activez Prochaine réunion dans Fonctions → Îlot et autorisez l’accès.")
    static let noAgents = Phrase("No AI agents are running right now.", ru: "Сейчас ИИ-агенты не запущены.", uk: "Зараз ШІ-агенти не запущені.",
                                 fr: "Aucun agent IA ne tourne en ce moment.")
    static let nothingCopied = Phrase("Nothing like that in the clipboard history.", ru: "В истории буфера такого нет.", uk: "В історії буфера такого немає.",
                                      fr: "Rien de tel dans l’historique du presse-papiers.")
    static let checkMac = Phrase("Check this Mac", ru: "Проверить Mac", uk: "Перевірити Mac", fr: "Vérifier ce Mac")
    static let sortDownloads = Phrase("Sort Downloads", ru: "Разобрать Загрузки", uk: "Розібрати Завантаження", fr: "Trier les Téléchargements")
    static let summarize = Phrase("Summarize", ru: "Пересказать", uk: "Переказати", fr: "Résumer")
    static let summarizePrompt = Phrase("Summarize what I brought in a few short points.", ru: "Кратко перескажи то, что я приложил, в нескольких пунктах.",
                                        uk: "Коротко перекажи те, що я додав, кількома пунктами.", fr: "Résume ce que j’ai apporté en quelques points courts.")
    static let allow = Phrase("Allow", ru: "Разрешить", uk: "Дозволити", fr: "Autoriser")
    static let deny = Phrase("Deny", ru: "Отклонить", uk: "Відхилити", fr: "Refuser")
    static let allowed = Phrase("Allowed", ru: "Разрешено", uk: "Дозволено", fr: "Autorisé")
    static let denied = Phrase("Denied", ru: "Отклонено", uk: "Відхилено", fr: "Refusé")
    static let expired = Phrase("No answer: not done", ru: "Нет ответа — не выполнено", uk: "Немає відповіді — не виконано", fr: "Sans réponse : non fait")
    static let retrying = Phrase("The model went in circles: asking once more", ru: "Модель зациклилась — прошу ещё раз",
                                 uk: "Модель зациклилася — прошу ще раз", fr: "Le modèle tournait en rond : nouvelle demande")
    static let cutOff = Phrase("The answer limit cut a file off: asking again with more room", ru: "Ответ упёрся в лимит — прошу ещё раз, с запасом",
                               uk: "Відповідь уперлася в ліміт — прошу ще раз, із запасом",
                               fr: "La limite de réponse a coupé un fichier : nouvelle demande avec plus de place")
    static let overflow = Phrase("The chat didn't fit the model's window: shortened and sent again",
                                 ru: "Разговор не поместился в окно модели — сократил и отправил снова",
                                 uk: "Розмова не вмістилася у вікно моделі — скоротив і надіслав знову",
                                 fr: "La conversation dépassait la fenêtre du modèle : raccourcie et renvoyée")
    static let tainted = Phrase("Text from someone else (a page, a file, the clipboard) shaped this request. Check it’s what you want.",
                                ru: "На этот запрос повлиял чужой текст (страница, файл, буфер обмена). Убедитесь, что это то, что вы хотите.",
                                uk: "На цей запит вплинув чужий текст (сторінка, файл, буфер обміну). Переконайтеся, що це те, чого ви хочете.",
                                fr: "Un texte venu d’ailleurs (une page, un fichier, le presse-papiers) a influencé cette demande. Vérifiez que c’est bien ce que vous voulez.")
    static let memory = Phrase("Memory", ru: "Память", uk: "Памʼять", fr: "Mémoire")
    static let heaviest = Phrase("Heaviest", ru: "Тяжелее всех", uk: "Найважчі", fr: "Les plus lourds")
    static let open = Phrase("Open", ru: "Открыть", uk: "Відкрити", fr: "Ouvrir")

    // Mac health, said from the numbers
    static let allFine = Phrase("All good: nothing stands out.", ru: "Всё в порядке: ничего необычного.", uk: "Усе гаразд: нічого незвичного.",
                                fr: "Tout va bien : rien d’anormal.")
    static let memoryFull = Phrase("Memory is nearly full.", ru: "Память почти заполнена.", uk: "Памʼять майже заповнена.", fr: "La mémoire est presque pleine.")
    static let cpuBusy = Phrase("The processor is busy.", ru: "Процессор сильно загружен.", uk: "Процесор сильно завантажений.", fr: "Le processeur est très occupé.")
    static let hot = Phrase("The Mac is running hot.", ru: "Mac перегревается.", uk: "Mac перегрівається.", fr: "Le Mac chauffe.")
    static let batteryLow = Phrase("The battery is low.", ru: "Батарея почти разряжена.", uk: "Батарея майже розряджена.", fr: "La batterie est faible.")
    static let diskLow = Phrase("The startup disk is nearly full.", ru: "Загрузочный диск почти заполнен.", uk: "Завантажувальний диск майже заповнений.",
                                fr: "Le disque de démarrage est presque plein.")
    static let nothingToSort = Phrase("Nothing to sort: the folder is already tidy.", ru: "Разбирать нечего: в папке уже порядок.",
                                      uk: "Розбирати нічого: у теці вже лад.", fr: "Rien à trier : le dossier est déjà rangé.")

    @MainActor static func memoryLine(_ free: Double, _ total: Double) -> String {
        Phrase("Memory: %.1f of %.0f GB free", ru: "Память: свободно %.1f из %.0f ГБ", uk: "Памʼять: вільно %.1f з %.0f ГБ",
               fr: "Mémoire : %.1f Go libres sur %.0f")(free, total)
    }

    @MainActor static func cpuLine(_ percent: Int) -> String {
        Phrase("Processor: %d%% busy", ru: "Процессор: загружен на %d%%", uk: "Процесор: завантажений на %d%%", fr: "Processeur : occupé à %d %%")(percent)
    }

    @MainActor static func diskLine(_ free: Double, _ total: Double) -> String {
        Phrase("Disk: %.0f of %.0f GB free", ru: "Диск: свободно %.0f из %.0f ГБ", uk: "Диск: вільно %.0f з %.0f ГБ", fr: "Disque : %.0f Go libres sur %.0f")(free, total)
    }

    @MainActor static func batteryLine(_ percent: Int) -> String {
        Phrase("Battery: %d%%", ru: "Батарея: %d%%", uk: "Батарея: %d%%", fr: "Batterie : %d %%")(percent)
    }

    /// How much of the processor one app takes, in cores: "214%" means nothing to most people.
    @MainActor static func busiest(_ name: String, cores: Double) -> String {
        Phrase("%@ keeps %.1f processor cores busy", ru: "%@ загружает %.1f ядра процессора", uk: "%@ завантажує %.1f ядра процесора",
               fr: "%@ occupe %.1f cœurs du processeur")(name, cores)
    }

    @MainActor static func gigabytes(_ value: Double) -> String {
        Phrase("%.1f GB", ru: "%.1f ГБ", uk: "%.1f ГБ", fr: "%.1f Go")(value)
    }

    @MainActor static func sorted(_ count: Int) -> String {
        Phrase("Sorted files: %d. Undo puts them back.", ru: "Разложено файлов: %d. «Отменить» вернёт всё как было.",
               uk: "Розкладено файлів: %d. «Скасувати» поверне все як було.", fr: "Fichiers rangés : %d. Annuler remet tout en place.")(count)
    }

    @MainActor static func agentLine(_ name: String, working: Bool, project: String?, minutes: Int?) -> String {
        let state = working ? Phrase("working", ru: "работает", uk: "працює", fr: "travaille").text : Phrase("waiting", ru: "ждёт", uk: "чекає", fr: "attend").text
        var line = "\(name): \(state)"
        if let project, !project.isEmpty { line += Phrase(" on %@", ru: " над %@", uk: " над %@", fr: " sur %@")(project) }
        if let minutes, minutes > 0 { line += " · " + Phrase("%d min", ru: "%d мин", uk: "%d хв", fr: "%d min")(minutes) }
        return line
    }

    /// A feature's name for people: the group's name for its main switch ("Panda"), the option's own otherwise.
    @MainActor static func featureName(_ id: String) -> String {
        if let group = FeatureGroup.all.first(where: { $0.main.id == id }) { return group.title.text }
        return FeatureGroup.all.flatMap(\.options).first { $0.id == id }?.title.text ?? id
    }

    @MainActor static func switched(_ name: String, on: Bool) -> String {
        on ? Phrase("Turned on: %@.", ru: "Включено: %@.", uk: "Увімкнено: %@.", fr: "Activé : %@.")(name)
           : Phrase("Turned off: %@. It comes back the same way, or in Features.", ru: "Выключено: %@. Вернуть можно так же или в «Функциях».",
                    uk: "Вимкнено: %@. Повернути можна так само або у «Функціях».", fr: "Désactivé : %@. Réactivez-le de la même façon, ou dans Fonctions.")(name)
    }

    /// What an undo put back. The records sum up in English, so other languages get the count.
    @MainActor static func undone(_ summaries: [String]) -> String {
        guard !summaries.isEmpty else { return nothingToUndo.text }
        if Suite.shared.language == .en { return "Undone: " + summaries.joined(separator: "; ") }
        return Phrase("Undone, changes: %d", ru: "Отменено изменений: %d", uk: "Скасовано змін: %d", fr: "Modifications annulées : %d")(summaries.count)
    }

    // Settings
    static let group = Phrase("Assistant", ru: "Ассистент", uk: "Асистент", fr: "Assistant")
    static let groupDetail = Phrase("Asks, plans and acts on this Mac, with your consent.", ru: "Отвечает, планирует и действует на этом Mac — с вашего согласия.",
                                    uk: "Відповідає, планує й діє на цьому Mac — з вашої згоди.", fr: "Répond, planifie et agit sur ce Mac, avec votre accord.")
    static let enable = Phrase("Assistant", ru: "Ассистент", uk: "Асистент", fr: "Assistant")
    static let enableDetail = Phrase("Runs on Mould Engine: local models first, every action checked and journaled",
                                     ru: "Работает на Mould Engine: сначала локальные модели, каждое действие проверяется и записывается в журнал",
                                     uk: "Працює на Mould Engine: спершу локальні моделі, кожна дія перевіряється й записується в журнал",
                                     fr: "Tourne sur Mould Engine : modèles locaux d’abord, chaque action vérifiée et journalisée")
    static let hotkey = Phrase("Open the assistant", ru: "Открывать ассистента", uk: "Відкривати асистента", fr: "Ouvrir l’assistant")
    static let mode = Phrase("Where it thinks", ru: "Где думает", uk: "Де думає", fr: "Où il réfléchit")
    static let personalToCloud = Phrase("Personal data may go to the cloud model", ru: "Личные данные можно отправлять облачной модели",
                                        uk: "Особисті дані можна надсилати хмарній моделі", fr: "Les données personnelles peuvent aller au modèle cloud")
    static let personalDetail = Phrase("Off: your files, selection and calendar stay on this Mac; such requests use the local model",
                                       ru: "Если выключено, ваши файлы, выделенное и календарь не покидают этот Mac — такие запросы идут к локальной модели",
                                       uk: "Якщо вимкнено, ваші файли, виділене й календар не залишають цей Mac — такі запити йдуть до локальної моделі",
                                       fr: "Désactivé : vos fichiers, votre sélection et votre agenda restent sur ce Mac ; ces demandes vont au modèle local")
    static let localModel = Phrase("Local model", ru: "Локальная модель", uk: "Локальна модель", fr: "Modèle local")
    static let cloudModel = Phrase("Cloud model", ru: "Облачная модель", uk: "Хмарна модель", fr: "Modèle cloud")
    static let cloudFromAI = Phrase("From the AI settings", ru: "Из настроек ИИ", uk: "З налаштувань ШІ", fr: "Depuis les réglages IA")
    static let none = Phrase("None", ru: "Нет", uk: "Немає", fr: "Aucun")
    static let loaded = Phrase("In memory", ru: "В памяти", uk: "У памʼяті", fr: "En mémoire")
    static let download = Phrase("Download", ru: "Скачать", uk: "Завантажити", fr: "Télécharger")
    static let fellBack = Phrase("Your model didn’t answer, so one on this Mac does.", ru: "Ваша модель не ответила — отвечает модель на этом Mac.",
                                 uk: "Ваша модель не відповіла — відповідає модель на цьому Mac.", fr: "Votre modèle n’a pas répondu ; un modèle de ce Mac prend le relais.")
    static let ownModel = Phrase("The assistant thinks with this model, your key. Models on this Mac step in without internet, or if you choose Only on this Mac.",
                                 ru: "Ассистент думает этой моделью, по вашему ключу. Модели на этом Mac выручат без интернета или если выбрать «Только на этом Mac».",
                                 uk: "Асистент думає цією моделлю, за вашим ключем. Моделі на цьому Mac виручать без інтернету або якщо вибрати «Лише на цьому Mac».",
                                 fr: "L’assistant réfléchit avec ce modèle, votre clé. Les modèles de ce Mac prennent le relais sans internet, ou si vous choisissez Uniquement sur ce Mac.")
    static let betterModel = Phrase("Understands much better, Russian and Ukrainian included. The current one stays for when memory is short.",
                                    ru: "Понимает намного лучше, в том числе по-русски и по-украински. Текущая модель останется на случай, когда памяти мало.",
                                    uk: "Розуміє набагато краще, зокрема українською та російською. Поточна модель залишиться на випадок, коли памʼяті мало.",
                                    fr: "Comprend bien mieux, russe et ukrainien compris. L’actuel reste pour quand la mémoire manque.")
    static let downloadFailed = Phrase("The download didn’t finish", ru: "Загрузка не завершилась", uk: "Завантаження не завершилося", fr: "Le téléchargement n’a pas abouti")
    static let checksum = Phrase("The downloaded file isn’t the expected model, so it was deleted", ru: "Скачанный файл не совпал с ожидаемой моделью и удалён",
                                 uk: "Завантажений файл не збігся з очікуваною моделлю й видалений", fr: "Le fichier téléchargé n’est pas le modèle attendu ; il a été supprimé")
    static let folders = Phrase("Folders it may work in", ru: "Папки, где можно работать", uk: "Теки, де можна працювати", fr: "Dossiers où il peut travailler")
    static let foldersDetail = Phrase("Files you select are added for one request. Everything else, including ~/Library, passwords and system files, stays out of reach.",
                                      ru: "Выделенные файлы добавляются на один запрос. Всё остальное, включая ~/Library, пароли и системные файлы, недоступно.",
                                      uk: "Виділені файли додаються на один запит. Усе інше, зокрема ~/Library, паролі й системні файли, недоступне.",
                                      fr: "Les fichiers sélectionnés sont ajoutés pour une demande. Le reste, dont ~/Library, les mots de passe et les fichiers système, reste hors de portée.")
    static let addFolder = Phrase("Add a folder…", ru: "Добавить папку…", uk: "Додати теку…", fr: "Ajouter un dossier…")
    static let memories = Phrase("Remembered: %d", ru: "Запомнено: %d", uk: "Запамʼятовано: %d", fr: "Mémorisé : %d")
    static let forget = Phrase("Forget everything", ru: "Забыть всё", uk: "Забути все", fr: "Tout oublier")
    static let journal = Phrase("Journal", ru: "Журнал", uk: "Журнал", fr: "Journal")

    static func modeTitle(_ mode: RouterPolicy.Mode) -> Phrase {
        switch mode {
        case .localOnly: Phrase("Only on this Mac", ru: "Только на этом Mac", uk: "Лише на цьому Mac", fr: "Uniquement sur ce Mac")
        case .localFirst: Phrase("This Mac first", ru: "Сначала на этом Mac", uk: "Спершу на цьому Mac", fr: "Ce Mac d’abord")
        case .balanced: Phrase("Whatever fits best", ru: "Как лучше подходит", uk: "Як краще пасує", fr: "Au mieux")
        case .bestQuality: Phrase("Strongest model", ru: "Самая сильная модель", uk: "Найсильніша модель", fr: "Le modèle le plus fort")
        }
    }

    @MainActor static func files(_ count: Int) -> String {
        Phrase("Files: %d", ru: "Файлов: %d", uk: "Файлів: %d", fr: "Fichiers : %d")(count)
    }

    @MainActor static func andMore(_ count: Int) -> String {
        Phrase("and %d more", ru: "и ещё %d", uk: "і ще %d", fr: "et %d de plus")(count)
    }

    /// The sorted folders' names in the person's language.
    @MainActor static var folderNames: JSONValue {
        let names: [String: Phrase] = [
            "Images": Phrase("Images", ru: "Картинки", uk: "Зображення", fr: "Images"),
            "Documents": Phrase("Documents", ru: "Документы", uk: "Документи", fr: "Documents"),
            "Spreadsheets": Phrase("Spreadsheets", ru: "Таблицы", uk: "Таблиці", fr: "Tableurs"),
            "Presentations": Phrase("Presentations", ru: "Презентации", uk: "Презентації", fr: "Présentations"),
            "Archives": Phrase("Archives", ru: "Архивы", uk: "Архіви", fr: "Archives"),
            "Audio": Phrase("Audio", ru: "Аудио", uk: "Аудіо", fr: "Audio"),
            "Video": Phrase("Video", ru: "Видео", uk: "Відео", fr: "Vidéos"),
            "Code": Phrase("Code", ru: "Код", uk: "Код", fr: "Code"),
            "Other": Phrase("Other", ru: "Другое", uk: "Інше", fr: "Autres")
        ]
        return .object(names.mapValues { .string($0.text) })
    }

    /// A tool's name for people, in their language; tools SAVISUL doesn't know keep the engine's English title.
    @MainActor static func tool(_ name: ToolName, _ fallback: String) -> String {
        tools[name.rawValue]?.text ?? fallback
    }

    private static let tools: [String: Phrase] = [
        "memory.remember": Phrase("Remember", ru: "Запомнить", uk: "Запамʼятати", fr: "Mémoriser"),
        "memory.recall": Phrase("Recall", ru: "Вспомнить", uk: "Пригадати", fr: "Se souvenir"),
        "memory.forget": Phrase("Forget", ru: "Забыть", uk: "Забути", fr: "Oublier"),
        "mac.resources": Phrase("Memory, CPU and battery", ru: "Память, процессор и батарея", uk: "Памʼять, процесор і батарея", fr: "Mémoire, processeur et batterie"),
        "mac.processes": Phrase("What uses memory and CPU", ru: "Что занимает память и процессор", uk: "Що займає памʼять і процесор", fr: "Ce qui utilise la mémoire et le processeur"),
        "mac.apps": Phrase("Open apps", ru: "Открытые приложения", uk: "Відкриті застосунки", fr: "Apps ouvertes"),
        "mac.disks": Phrase("Disk space", ru: "Место на дисках", uk: "Місце на дисках", fr: "Espace disque"),
        "mac.health": Phrase("Mac health check", ru: "Проверка Mac", uk: "Перевірка Mac", fr: "Bilan du Mac"),
        "automations.list": Phrase("List automations", ru: "Список автоматизаций", uk: "Список автоматизацій", fr: "Liste des automatisations"),
        "automations.create": Phrase("Create an automation", ru: "Создать автоматизацию", uk: "Створити автоматизацію", fr: "Créer une automatisation"),
        "automations.set_enabled": Phrase("Turn an automation on or off", ru: "Включить или выключить автоматизацию", uk: "Увімкнути чи вимкнути автоматизацію",
                                          fr: "Activer ou désactiver une automatisation"),
        "automations.run": Phrase("Run an automation now", ru: "Запустить автоматизацию", uk: "Запустити автоматизацію", fr: "Lancer une automatisation"),
        "shelf.add": Phrase("Put on the Shelf", ru: "Положить на полку", uk: "Покласти на полицю", fr: "Mettre sur l’étagère"),
        "clipboard.search": Phrase("Search clipboard history", ru: "Поиск в истории буфера", uk: "Пошук в історії буфера", fr: "Chercher dans l’historique du presse-papiers"),
        "clipboard.copy": Phrase("Copy", ru: "Скопировать", uk: "Скопіювати", fr: "Copier"),
        "island.notify": Phrase("Show in the island", ru: "Показать в островке", uk: "Показати в острівці", fr: "Afficher dans l’îlot"),
        "agents.status": Phrase("AI agents", ru: "ИИ-агенты", uk: "ШІ-агенти", fr: "Agents IA"),
        "calendar.upcoming": Phrase("Upcoming meetings", ru: "Ближайшие встречи", uk: "Найближчі зустрічі", fr: "Prochaines réunions"),
        "savisul.feature": Phrase("Turn a SAVISUL feature on or off", ru: "Включить или выключить функцию SAVISUL", uk: "Увімкнути чи вимкнути функцію SAVISUL",
                                  fr: "Activer ou désactiver une fonction de SAVISUL"),
        "images.recognize_text": Phrase("Read text in an image", ru: "Распознать текст на картинке", uk: "Розпізнати текст на зображенні", fr: "Lire le texte d’une image"),
        "images.convert": Phrase("Convert images", ru: "Конвертировать картинки", uk: "Конвертувати зображення", fr: "Convertir des images"),
        "photos.find": Phrase("Find photos", ru: "Поиск фото", uk: "Пошук фото", fr: "Recherche de photos"),
        "photos.understand": Phrase("Understanding the description", ru: "Понимаю описание", uk: "Розумію опис", fr: "Compréhension de la description"),
        "files.list": Phrase("List a folder", ru: "Содержимое папки", uk: "Вміст теки", fr: "Contenu d’un dossier"),
        "files.info": Phrase("File details", ru: "Сведения о файле", uk: "Відомості про файл", fr: "Détails du fichier"),
        "files.search": Phrase("Find files", ru: "Найти файлы", uk: "Знайти файли", fr: "Trouver des fichiers"),
        "files.read_text": Phrase("Read a text file", ru: "Прочитать текстовый файл", uk: "Прочитати текстовий файл", fr: "Lire un fichier texte"),
        "files.large_files": Phrase("Largest files", ru: "Самые большие файлы", uk: "Найбільші файли", fr: "Fichiers les plus lourds"),
        "files.make_folder": Phrase("New folder", ru: "Новая папка", uk: "Нова тека", fr: "Nouveau dossier"),
        "files.move": Phrase("Move files", ru: "Переместить файлы", uk: "Перемістити файли", fr: "Déplacer des fichiers"),
        "files.rename": Phrase("Rename", ru: "Переименовать", uk: "Перейменувати", fr: "Renommer"),
        "files.copy": Phrase("Copy files", ru: "Скопировать файлы", uk: "Скопіювати файли", fr: "Copier des fichiers"),
        "files.trash": Phrase("Move to Trash", ru: "Переместить в корзину", uk: "Перемістити в кошик", fr: "Mettre à la corbeille"),
        "files.sort_folder": Phrase("Sort a folder", ru: "Разобрать папку", uk: "Розібрати теку", fr: "Trier un dossier"),
        "files.rename_by_date": Phrase("Rename by date", ru: "Переименовать по дате", uk: "Перейменувати за датою", fr: "Renommer par date"),
        "files.collect": Phrase("Gather files into a folder", ru: "Собрать файлы в папку", uk: "Зібрати файли в теку", fr: "Rassembler des fichiers dans un dossier")
    ]

    /// One change from a preview, in the person's language: "report.pdf → Documents".
    @MainActor static func change(_ change: Change) -> String {
        let name = URL(fileURLWithPath: change.subject).lastPathComponent
        let folder = change.detail.map { URL(fileURLWithPath: $0).deletingLastPathComponent().lastPathComponent }
        switch change.kind {
        case .move: return "\(name) → \(folder ?? "")"
        case .rename: return "\(name) → \(change.detail ?? "")"
        case .copy: return Phrase("Copy %@ to %@", ru: "Копия %@ в %@", uk: "Копія %@ у %@", fr: "Copie de %@ dans %@")(name, folder ?? "")
        case .create: return Phrase("New: %@", ru: "Новое: %@", uk: "Нове: %@", fr: "Nouveau : %@")(name)
        case .delete: return Phrase("To the Trash: %@", ru: "В корзину: %@", uk: "У кошик: %@", fr: "À la corbeille : %@")(name)
        case .modify: return Phrase("Changes: %@", ru: "Изменится: %@", uk: "Зміниться: %@", fr: "Modifié : %@")(name)
        case .open: return Phrase("Opens: %@", ru: "Откроется: %@", uk: "Відкриється: %@", fr: "Ouvre : %@")(change.subject)
        case .send: return Phrase("Sends: %@", ru: "Отправит: %@", uk: "Надішле: %@", fr: "Envoie : %@")(change.subject)
        case .setting:
            let value = switch change.detail {
            case "on": Phrase("on", ru: "вкл.", uk: "увімк.", fr: "activé").text
            case "off": Phrase("off", ru: "выкл.", uk: "вимк.", fr: "désactivé").text
            default: change.detail ?? ""
            }
            return "\(featureName(change.subject)): \(value)"
        case .other: return [change.subject, change.detail].compactMap { $0 }.joined(separator: " ")
        }
    }

    /// An engine error, said in the person's language where SAVISUL knows the kind.
    @MainActor static func error(_ error: MouldError) -> String {
        switch error {
        case .declined: Phrase("Not done: you said no", ru: "Не выполнено: вы отказались", uk: "Не виконано: ви відмовилися", fr: "Non fait : vous avez refusé").text
        case .denied(let reason): Phrase("Not allowed: %@", ru: "Не разрешено: %@", uk: "Не дозволено: %@", fr: "Non autorisé : %@")(reason)
        case .outOfScope(let what): Phrase("Outside the folders it may use: %@. Add the folder in Settings → Features → Assistant, or select the files first.",
                                           ru: "Вне разрешённых папок: %@. Добавьте папку в Настройки → Функции → Ассистент или сначала выделите файлы.",
                                           uk: "Поза дозволеними теками: %@. Додайте теку в Налаштування → Функції → Асистент або спершу виділіть файли.",
                                           fr: "Hors des dossiers autorisés : %@. Ajoutez le dossier dans Réglages → Fonctions → Assistant, ou sélectionnez d’abord les fichiers.")(what)
        case .forbidden(let what): Phrase("Never allowed: %@", ru: "Запрещено всегда: %@", uk: "Заборонено завжди: %@", fr: "Jamais autorisé : %@")(what)
        case .timeout(let what): Phrase("Took too long: %@", ru: "Слишком долго: %@", uk: "Надто довго: %@", fr: "Trop long : %@")(what)
        case .unavailable(let what): Phrase("Unavailable: %@", ru: "Недоступно: %@", uk: "Недоступно: %@", fr: "Indisponible : %@")(what)
        case .backend(let message, _): Phrase("The model failed: %@", ru: "Ошибка модели: %@", uk: "Помилка моделі: %@", fr: "Le modèle a échoué : %@")(message)
        case .cancelled: stopped.text
        default: error.description
        }
    }
}
#endif
