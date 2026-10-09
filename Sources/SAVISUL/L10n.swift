import Foundation

enum Language: String, CaseIterable, Identifiable {
    case en, ru, uk, fr

    var id: String { rawValue }

    var nativeName: String {
        switch self {
        case .en: "English"
        case .ru: "Русский"
        case .uk: "Українська"
        case .fr: "Français"
        }
    }

    var locale: Locale {
        switch self {
        case .en: Locale(identifier: "en_US")
        case .ru: Locale(identifier: "ru_RU")
        case .uk: Locale(identifier: "uk_UA")
        case .fr: Locale(identifier: "fr_FR")
        }
    }
}

enum Copy: String {
    case tabEnergy, tabSound, tabSystem, tabWork, tabTools, tabFeatures, tabSettings, moreMenu, featuresSubtitle, tabAutomations
    case menuKeepOpen, menuDisplayOff, menuScreenshot, menuSettings, menuActivityMonitor, menuQuit, chipAwake
    case mmAbout, mmSettings, mmHide, mmQuit, mmEdit, mmUndo, mmRedo, mmCut, mmCopy, mmPaste, mmSelectAll

    case energyOn, energyOff, lidTitle, lidOn, lidOff, lidWaiting, lidOnFor, lidExplainOff, lidExplainOn
    case batteryConfirmTitle, batteryConfirmBody, turnOn, cancel, errCancelled, errFailed, errVerify
    case adminPromptOn, adminPromptOff, rowPower, rowIdleSleep, rowHeldBy
    case srcBattery, srcCharging, srcAdapter, srcNone, timeLeft, timeToFull, sleepNever, sleepAfter
    case idleTitle, idleDetail, restoredTimers

    case muted, output, input, balance, centerWord, leftShort, rightShort, mute, unmute, fineHint
    case playingNow, silence, noVolume, wholeDevice, noDevices

    case systemSubtitle, processor, memory, battery, temperature, memoryOf
    case pressureNormal, pressureWarning, pressureCritical, swapUsed, healthLine, chipSensor
    case busiestApps, measuring, fans, fanName, fanStopped, fanRange, fanSpeed, fansIdle, fanNote, fanNone, noSensor

    case workSubtitleToday, workSubtitleWeek, today, sevenDays, inEditors, aiApps, typed, tokensApprox
    case groupEditors, groupAssistants, groupOther, showMore, showLess
    case keysTitle, keysBody, keysWaiting, keysFailed, typingOn, allow, openSettings, reopen
    case workEmpty, tokenNote, charsTokens

    case toolsSubtitle, capture, capSelection, capWindow, capScreen, capRecord, capStop, capToolbar
    case capSaved, videoSaved, recordFailed, captureFailed, lastCapture, revealInFinder, openFile, copyAgain, copied
    case screenTitle, screenBody, screenAfter
    case alertsTitle, alertsBody, alertCPU, alertMemory, alertBattery, alertHeat, alertDone, alertDoneDetail
    case sendTest, notifOff
    case utilities, builtIn, yourUtilities, addUtility, fieldName, fieldTarget, shellCommand, chooseApp, remove
    case utilitiesEmpty, uActivity, uTerminal, uSettings, uDisk, uDisplayOff, uCopyIP, uHidden
    case ipCopied, ipNone, hiddenShown, hiddenHidden, runDone, runFailed, openFailed, run
    case nCPU, nMemory, nBattery, nBatteryLid, nHeat, nDone, nTest
    case browserTitle, browserIdle, browserConnected, browserStep1, browserStep2, browserStep3
    case browserReveal, browserOpen

    case settingsSubtitle, language, general, openAtLogin, showInDock, keepOpen, keepOpenDetail
    case shortcut, shortcutDetail, shortcutBusy, permissions, permissionsNote
    case permAccessibility, permAccessibilityUse, permScreen, permScreenUse
    case permNotifications, permNotificationsUse, permLogin, permLoginUse, permAdmin, permAdminUse
    case stAllowed, stOff, stNotAsked, stApproval, stAskEachTime, menuBarHidden, dockForced, loginFailed
}

enum L10n {
    static func text(_ key: Copy, _ language: Language) -> String {
        tables[language]?[key] ?? english[key] ?? key.rawValue
    }

    static func format(_ key: Copy, _ language: Language, _ arguments: [String]) -> String {
        String(format: text(key, language), locale: language.locale, arguments: arguments.map { $0 as CVarArg })
    }

    static func duration(_ seconds: Double, _ language: Language) -> String {
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let units: (h: String, m: String, s: String, gap: String) = switch language {
        case .en: ("h", "m", "s", "")
        case .ru: ("ч", "мин", "с", " ")
        case .uk: ("год", "хв", "с", " ")
        case .fr: ("h", "min", "s", " ")
        }
        if hours > 0 {
            return minutes > 0
                ? "\(hours)\(units.gap)\(units.h) \(minutes)\(units.gap)\(units.m)"
                : "\(hours)\(units.gap)\(units.h)"
        }
        if minutes > 0 { return "\(minutes)\(units.gap)\(units.m)" }
        return "\(total)\(units.gap)\(units.s)"
    }

    private static let tables: [Language: [Copy: String]] = [.en: english, .ru: russian, .uk: ukrainian, .fr: french]

    private static let english: [Copy: String] = [
        .tabEnergy: "Energy", .tabSound: "Sound", .tabSystem: "System", .tabWork: "Work", .tabTools: "Tools",
        .tabFeatures: "Features", .featuresSubtitle: "%@ of %@ turned on",
        .tabSettings: "Settings", .moreMenu: "More", .tabAutomations: "Automations",
        .menuKeepOpen: "Keep open", .menuDisplayOff: "Display off", .menuScreenshot: "Screenshot",
        .menuSettings: "Settings", .menuActivityMonitor: "Activity Monitor", .menuQuit: "Quit SAVISUL",
        .chipAwake: "Awake",
        .mmAbout: "About SAVISUL", .mmSettings: "Settings…", .mmHide: "Hide SAVISUL", .mmQuit: "Quit SAVISUL",
        .mmEdit: "Edit", .mmUndo: "Undo", .mmRedo: "Redo", .mmCut: "Cut", .mmCopy: "Copy", .mmPaste: "Paste",
        .mmSelectAll: "Select All",

        .energyOn: "The Mac keeps working with the lid closed",
        .energyOff: "Closing the lid puts the Mac to sleep",
        .lidTitle: "Closed-lid mode",
        .lidOn: "On", .lidOff: "Off", .lidWaiting: "Waiting for your password…", .lidOnFor: "On for %@",
        .lidExplainOff: "Turn it on before you close the lid, and downloads, builds and local AI models keep running. macOS asks for your administrator password.",
        .lidExplainOn: "System sleep stays off until you turn this off here, even if you quit SAVISUL.",
        .batteryConfirmTitle: "Running on battery",
        .batteryConfirmBody: "With the lid closed the Mac keeps working and drains the battery. Plug in the adapter for long jobs.",
        .turnOn: "Turn on", .cancel: "Cancel",
        .errCancelled: "Password entry was cancelled. Nothing changed.",
        .errFailed: "macOS didn't apply the change: %@",
        .errVerify: "The command ran, but the sleep setting didn't change. Try again.",
        .adminPromptOn: "SAVISUL needs your password to keep the Mac awake with the lid closed.",
        .adminPromptOff: "SAVISUL needs your password to let the Mac sleep again.",
        .rowPower: "Power", .rowIdleSleep: "Idle sleep", .rowHeldBy: "Kept awake by",
        .srcBattery: "Battery", .srcCharging: "Charging", .srcAdapter: "Power adapter", .srcNone: "No battery",
        .timeLeft: "%@ left", .timeToFull: "full in %@", .sleepNever: "Never", .sleepAfter: "After %@",
        .idleTitle: "Prevent idle sleep",
        .idleDetail: "Stays awake while the lid is open. No password needed.",
        .restoredTimers: "Sleep timers are back to the values you had before.",

        .muted: "muted", .output: "Output", .input: "Input", .balance: "Balance", .centerWord: "Center",
        .leftShort: "L", .rightShort: "R", .mute: "Mute", .unmute: "Unmute",
        .fineHint: "Hold ⌥ while dragging for 0.1% steps.",
        .playingNow: "Playing now", .silence: "Nothing is playing",
        .noVolume: "This device has no volume control.",
        .wholeDevice: "Levels apply to the whole device.", .noDevices: "No devices",

        .systemSubtitle: "Processor %@ · Memory %@",
        .processor: "Processor", .memory: "Memory", .battery: "Battery", .temperature: "Temperature",
        .memoryOf: "%@ of %@",
        .pressureNormal: "Normal pressure", .pressureWarning: "High pressure", .pressureCritical: "Critical pressure",
        .swapUsed: "Swap %@", .healthLine: "Health %@ · %@ cycles", .chipSensor: "Chip sensor",
        .busiestApps: "Busiest apps", .measuring: "Measuring…",
        .fans: "Fans", .fanName: "Fan %@", .fanStopped: "Stopped", .fanRange: "%@–%@ rpm", .fanSpeed: "%@ rpm", .fansIdle: "Fans are stopped",
        .fanNote: "macOS controls fan speed on Apple silicon. SAVISUL shows it live and warns you when the chip runs hot.",
        .fanNone: "This Mac doesn't report fan speed.", .noSensor: "No sensor",

        .workSubtitleToday: "%@ in editors today", .workSubtitleWeek: "%@ in editors this week",
        .today: "Today", .sevenDays: "7 days",
        .inEditors: "In editors", .aiApps: "AI apps", .typed: "Typed", .tokensApprox: "≈ Tokens",
        .groupEditors: "Editors", .groupAssistants: "AI assistants", .groupOther: "Other apps",
        .showMore: "Show %@ more", .showLess: "Show less",
        .keysTitle: "Count typing",
        .keysBody: "Characters and tokens need Accessibility access. SAVISUL stores counts only, never the text.",
        .keysWaiting: "Turn on SAVISUL in Accessibility. This card updates by itself.",
        .keysFailed: "Access is on, but macOS didn't start the keyboard monitor. Reopen SAVISUL.",
        .typingOn: "Typing is counted",
        .allow: "Allow", .openSettings: "Open Settings", .reopen: "Reopen",
        .workEmpty: "Screen time shows up here as you work in apps. Idle time isn't counted.",
        .tokenNote: "Tokens are estimated from what you type: about 4 Latin or 2 Cyrillic characters per token.",
        .charsTokens: "%@ chars · ≈%@ tokens",

        .toolsSubtitle: "Capture, alerts and utilities",
        .capture: "Capture", .capSelection: "Selection", .capWindow: "Window", .capScreen: "Screen",
        .capRecord: "Record", .capStop: "Stop", .capToolbar: "Toolbar",
        .capSaved: "Saved and copied to the clipboard", .videoSaved: "Recording saved",
        .recordFailed: "Recording didn't start. Use the Toolbar instead.", .captureFailed: "Capture didn't start.",
        .lastCapture: "Last capture", .revealInFinder: "Show in Finder", .openFile: "Open", .copyAgain: "Copy",
        .copied: "Copied",
        .screenTitle: "Screen Recording",
        .screenBody: "One-click captures need Screen Recording access. The Toolbar button works without it.",
        .screenAfter: "Turn SAVISUL on there. This card updates by itself within a few seconds.",
        .alertsTitle: "Smart alerts", .alertsBody: "One notice per event, then quiet for 15 minutes.",
        .alertCPU: "Processor above", .alertMemory: "Memory above", .alertBattery: "Battery below",
        .alertHeat: "Chip above", .alertDone: "When heavy work finishes",
        .alertDoneDetail: "After 3 minutes or more of high load",
        .sendTest: "Send test", .notifOff: "Notifications are off for SAVISUL.",
        .utilities: "Utilities", .builtIn: "Built in", .yourUtilities: "Yours", .addUtility: "Add",
        .fieldName: "Name", .fieldTarget: "App path or shell command", .shellCommand: "Shell command",
        .chooseApp: "Choose app…", .remove: "Remove",
        .utilitiesEmpty: "Add an app or a shell command you use often.",
        .uActivity: "Activity", .uTerminal: "Terminal", .uSettings: "Settings", .uDisk: "Disks",
        .uDisplayOff: "Display off", .uCopyIP: "Copy IP", .uHidden: "Hidden files",
        .ipCopied: "Copied %@", .ipNone: "No network address",
        .hiddenShown: "Hidden files are visible", .hiddenHidden: "Hidden files are hidden",
        .runDone: "%@ finished", .runFailed: "%@ failed: %@", .openFailed: "Couldn't open %@", .run: "Run",
        .nCPU: "Processor has stayed above %@ for a minute.", .nMemory: "Memory is %@ full.",
        .nBattery: "Battery is at %@.", .nBatteryLid: "Battery is at %@ and closed-lid mode is on.",
        .nHeat: "Chip temperature reached %@.", .nDone: "Heavy work finished after %@.",
        .nTest: "Alerts from SAVISUL look like this.",
        .browserTitle: "Browser notch",
        .browserIdle: "Reader, eyedropper, ruler, notes, dark theme and full-page screenshots in Chrome, Edge, Brave, Arc or Yandex, with SAVISUL controls on top.",
        .browserConnected: "Works in %@: lid, sound and screenshots from any tab",
        .browserStep1: "Open the extensions page and turn on Developer mode.",
        .browserStep2: "Drag the Extension folder onto that page.",
        .browserStep3: "Open any website. The notch sits on the page, and the new tab stays Chrome’s own. ⌥⇧N.",
        .browserReveal: "Show folder",
        .browserOpen: "Extensions",

        .settingsSubtitle: "Version %@", .language: "Language", .general: "General",
        .openAtLogin: "Open at login", .showInDock: "Show in Dock", .keepOpen: "Keep panel open",
        .keepOpenDetail: "Clicking elsewhere won't close it",
        .shortcut: "Shortcut", .shortcutDetail: "Opens SAVISUL from anywhere",
        .shortcutBusy: "Another app already uses this shortcut",
        .permissions: "Permissions",
        .permissionsNote: "These update live: a change in System Settings shows up here within a few seconds.",
        .permAccessibility: "Accessibility", .permAccessibilityUse: "Counts typing in Work",
        .permScreen: "Screen Recording", .permScreenUse: "One-click screenshots and recording",
        .permNotifications: "Notifications", .permNotificationsUse: "Smart alerts",
        .permLogin: "Login item", .permLoginUse: "Starts SAVISUL when you log in",
        .permAdmin: "Administrator", .permAdminUse: "Asked each time you switch closed-lid mode",
        .stAllowed: "Allowed", .stOff: "Off", .stNotAsked: "Not requested", .stApproval: "Needs approval",
        .stAskEachTime: "Each time",
        .menuBarHidden: "The menu bar is full, so macOS hid the SAVISUL icon. Hold ⌘ and drag icons to make room. Until then, use the Dock icon or ⌃⌥S.",
        .dockForced: "Shown while the menu bar icon is hidden",
        .loginFailed: "macOS didn't add the login item: %@"
    ]

    private static let russian: [Copy: String] = [
        .tabEnergy: "Питание", .tabSound: "Звук", .tabSystem: "Система", .tabWork: "Работа", .tabTools: "Утилиты",
        .tabFeatures: "Возможности", .featuresSubtitle: "Включено %@ из %@",
        .tabSettings: "Настройки", .moreMenu: "Ещё", .tabAutomations: "Автоматизации",
        .menuKeepOpen: "Не закрывать", .menuDisplayOff: "Погасить экран", .menuScreenshot: "Снимок",
        .menuSettings: "Настройки", .menuActivityMonitor: "Мониторинг системы", .menuQuit: "Выйти из SAVISUL",
        .chipAwake: "Не спит",
        .mmAbout: "О программе SAVISUL", .mmSettings: "Настройки…", .mmHide: "Скрыть SAVISUL",
        .mmQuit: "Завершить SAVISUL", .mmEdit: "Правка", .mmUndo: "Отменить", .mmRedo: "Повторить",
        .mmCut: "Вырезать", .mmCopy: "Скопировать", .mmPaste: "Вставить", .mmSelectAll: "Выбрать все",

        .energyOn: "Mac работает и с закрытой крышкой",
        .energyOff: "Закрытая крышка усыпляет Mac",
        .lidTitle: "Режим закрытой крышки",
        .lidOn: "Включён", .lidOff: "Выключен", .lidWaiting: "Ждём пароль…", .lidOnFor: "Включён %@",
        .lidExplainOff: "Включите перед тем, как закрыть крышку: загрузки, сборки и локальные ИИ-модели продолжат работать. macOS запросит пароль администратора.",
        .lidExplainOn: "Системный сон выключен, пока вы не выключите режим здесь, даже если закрыть SAVISUL.",
        .batteryConfirmTitle: "Mac работает от батареи",
        .batteryConfirmBody: "С закрытой крышкой Mac продолжит работу и будет тратить заряд. Для долгих задач подключите адаптер.",
        .turnOn: "Включить", .cancel: "Отмена",
        .errCancelled: "Ввод пароля отменён. Ничего не изменилось.",
        .errFailed: "macOS не применил изменение: %@",
        .errVerify: "Команда выполнилась, но настройка сна не изменилась. Попробуйте ещё раз.",
        .adminPromptOn: "SAVISUL нужен пароль, чтобы Mac не засыпал с закрытой крышкой.",
        .adminPromptOff: "SAVISUL нужен пароль, чтобы Mac снова мог засыпать.",
        .rowPower: "Питание", .rowIdleSleep: "Сон при бездействии", .rowHeldBy: "Не дают уснуть",
        .srcBattery: "Батарея", .srcCharging: "Заряжается", .srcAdapter: "Адаптер питания", .srcNone: "Нет батареи",
        .timeLeft: "осталось %@", .timeToFull: "до полной %@", .sleepNever: "Никогда", .sleepAfter: "Через %@",
        .idleTitle: "Не засыпать от бездействия",
        .idleDetail: "Mac не уснёт сам, пока крышка открыта. Пароль не нужен.",
        .restoredTimers: "Таймеры сна вернулись к прежним значениям.",

        .muted: "без звука", .output: "Выход", .input: "Вход", .balance: "Баланс", .centerWord: "Центр",
        .leftShort: "Л", .rightShort: "П", .mute: "Выключить звук", .unmute: "Включить звук",
        .fineHint: "Удерживайте ⌥ при перетаскивании — шаг 0,1 %.",
        .playingNow: "Сейчас звучит", .silence: "Сейчас ничего не играет",
        .noVolume: "У этого устройства нет регулировки громкости.",
        .wholeDevice: "Уровни задаются для всего устройства.", .noDevices: "Нет устройств",

        .systemSubtitle: "Процессор %@ · Память %@",
        .processor: "Процессор", .memory: "Память", .battery: "Батарея", .temperature: "Температура",
        .memoryOf: "%@ из %@",
        .pressureNormal: "Нагрузка в норме", .pressureWarning: "Высокая нагрузка", .pressureCritical: "Критическая нагрузка",
        .swapUsed: "Подкачка %@", .healthLine: "Здоровье %@ · циклов: %@", .chipSensor: "Датчик чипа",
        .busiestApps: "Самые активные", .measuring: "Измеряю…",
        .fans: "Вентиляторы", .fanName: "Вентилятор %@", .fanStopped: "Остановлен", .fanRange: "%@–%@ об/мин", .fanSpeed: "%@ об/мин", .fansIdle: "Вентиляторы стоят",
        .fanNote: "На Apple silicon оборотами управляет macOS. SAVISUL показывает их вживую и предупредит, если чип перегреется.",
        .fanNone: "Этот Mac не сообщает обороты вентиляторов.", .noSensor: "Нет датчика",

        .workSubtitleToday: "%@ в редакторах сегодня", .workSubtitleWeek: "%@ в редакторах за неделю",
        .today: "Сегодня", .sevenDays: "7 дней",
        .inEditors: "В редакторах", .aiApps: "ИИ-приложения", .typed: "Набрано", .tokensApprox: "≈ Токенов",
        .groupEditors: "Редакторы", .groupAssistants: "ИИ-ассистенты", .groupOther: "Другие приложения",
        .showMore: "Показать ещё %@", .showLess: "Свернуть",
        .keysTitle: "Считать набор текста",
        .keysBody: "Для подсчёта символов и токенов нужен Универсальный доступ. SAVISUL хранит только числа, не текст.",
        .keysWaiting: "Включите SAVISUL в разделе «Универсальный доступ». Карточка обновится сама.",
        .keysFailed: "Доступ включён, но macOS не запустил отслеживание клавиатуры. Перезапустите SAVISUL.",
        .typingOn: "Набор считается",
        .allow: "Разрешить", .openSettings: "Открыть настройки", .reopen: "Перезапустить",
        .workEmpty: "Экранное время появится, когда вы поработаете в приложениях. Простой не считается.",
        .tokenNote: "Токены оцениваются по набранному тексту: примерно 4 латинских или 2 кириллических символа на токен.",
        .charsTokens: "%@ симв. · ≈%@ токенов",

        .toolsSubtitle: "Съёмка, оповещения и утилиты",
        .capture: "Съёмка", .capSelection: "Область", .capWindow: "Окно", .capScreen: "Экран",
        .capRecord: "Запись", .capStop: "Стоп", .capToolbar: "Панель",
        .capSaved: "Сохранено и скопировано в буфер", .videoSaved: "Запись сохранена",
        .recordFailed: "Запись не началась. Воспользуйтесь кнопкой «Панель».", .captureFailed: "Снимок не начался.",
        .lastCapture: "Последний снимок", .revealInFinder: "Показать в Finder", .openFile: "Открыть",
        .copyAgain: "Копировать", .copied: "Скопировано",
        .screenTitle: "Запись экрана",
        .screenBody: "Для съёмки в один щелчок нужен доступ к записи экрана. Кнопка «Панель» работает и без него.",
        .screenAfter: "Включите SAVISUL в настройках — карточка обновится сама через пару секунд.",
        .alertsTitle: "Умные оповещения", .alertsBody: "Одно уведомление на событие, затем 15 минут тишины.",
        .alertCPU: "Процессор выше", .alertMemory: "Память выше", .alertBattery: "Батарея ниже",
        .alertHeat: "Чип горячее", .alertDone: "Когда тяжёлая задача завершится",
        .alertDoneDetail: "После 3 и более минут высокой нагрузки",
        .sendTest: "Проверить", .notifOff: "Уведомления для SAVISUL выключены.",
        .utilities: "Утилиты", .builtIn: "Встроенные", .yourUtilities: "Ваши", .addUtility: "Добавить",
        .fieldName: "Название", .fieldTarget: "Путь к программе или команда", .shellCommand: "Команда оболочки",
        .chooseApp: "Выбрать программу…", .remove: "Удалить",
        .utilitiesEmpty: "Добавьте программу или команду, которой пользуетесь часто.",
        .uActivity: "Мониторинг", .uTerminal: "Терминал", .uSettings: "Настройки", .uDisk: "Диски",
        .uDisplayOff: "Погасить экран", .uCopyIP: "Копировать IP", .uHidden: "Скрытые файлы",
        .ipCopied: "Скопировано: %@", .ipNone: "Нет сетевого адреса",
        .hiddenShown: "Скрытые файлы видны", .hiddenHidden: "Скрытые файлы скрыты",
        .runDone: "«%@» выполнено", .runFailed: "«%@»: ошибка — %@", .openFailed: "Не удалось открыть «%@»",
        .run: "Запустить",
        .nCPU: "Процессор держится выше %@ уже минуту.", .nMemory: "Память заполнена на %@.",
        .nBattery: "Заряд батареи %@.", .nBatteryLid: "Заряд батареи %@, а режим закрытой крышки включён.",
        .nHeat: "Температура чипа достигла %@.", .nDone: "Тяжёлая задача завершилась через %@.",
        .nTest: "Так выглядят оповещения SAVISUL.",
        .browserTitle: "Чёлка в браузере",
        .browserIdle: "Режим чтения, пипетка, линейка, заметки, тёмная тема и скриншоты всей страницы в Chrome, Edge, Brave, Arc или Яндекс Браузере, плюс управление SAVISUL.",
        .browserConnected: "Работает в %@: крышка, звук и скриншоты из любой вкладки",
        .browserStep1: "Откройте страницу расширений и включите режим разработчика.",
        .browserStep2: "Перетащите на неё папку Extension.",
        .browserStep3: "Откройте любой сайт. Чёлка на странице, новая вкладка остаётся обычной. ⌥⇧N.",
        .browserReveal: "Показать папку",
        .browserOpen: "Расширения",

        .settingsSubtitle: "Версия %@", .language: "Язык", .general: "Основные",
        .openAtLogin: "Открывать при входе", .showInDock: "Показывать в Dock", .keepOpen: "Не закрывать панель",
        .keepOpenDetail: "Щелчок мимо панели не закроет её",
        .shortcut: "Сочетание клавиш", .shortcutDetail: "Открывает SAVISUL откуда угодно",
        .shortcutBusy: "Это сочетание уже занято другой программой",
        .permissions: "Разрешения",
        .permissionsNote: "Статусы обновляются сами: изменение в Системных настройках появится здесь через пару секунд.",
        .permAccessibility: "Универсальный доступ", .permAccessibilityUse: "Подсчёт набора в «Работе»",
        .permScreen: "Запись экрана", .permScreenUse: "Снимки и запись в один щелчок",
        .permNotifications: "Уведомления", .permNotificationsUse: "Умные оповещения",
        .permLogin: "Объект входа", .permLoginUse: "Запуск SAVISUL при входе",
        .permAdmin: "Администратор", .permAdminUse: "Запрашивается при каждом переключении режима крышки",
        .stAllowed: "Разрешено", .stOff: "Выключено", .stNotAsked: "Не запрошено", .stApproval: "Ждёт одобрения",
        .stAskEachTime: "Каждый раз",
        .menuBarHidden: "Строка меню переполнена, и macOS скрыл значок SAVISUL. Удерживайте ⌘ и перетащите значки, чтобы освободить место. А пока открывайте SAVISUL из Dock или сочетанием ⌃⌥S.",
        .dockForced: "Показывается, пока значок в строке меню скрыт",
        .loginFailed: "macOS не добавил объект входа: %@"
    ]

    private static let ukrainian: [Copy: String] = [
        .tabEnergy: "Живлення", .tabSound: "Звук", .tabSystem: "Система", .tabWork: "Робота", .tabTools: "Утиліти",
        .tabFeatures: "Можливості", .featuresSubtitle: "Увімкнено %@ з %@",
        .tabSettings: "Параметри", .moreMenu: "Ще", .tabAutomations: "Автоматизації",
        .menuKeepOpen: "Не закривати", .menuDisplayOff: "Вимкнути екран", .menuScreenshot: "Знімок",
        .menuSettings: "Параметри", .menuActivityMonitor: "Моніторинг системи", .menuQuit: "Вийти з SAVISUL",
        .chipAwake: "Не спить",
        .mmAbout: "Про SAVISUL", .mmSettings: "Параметри…", .mmHide: "Сховати SAVISUL", .mmQuit: "Вийти з SAVISUL",
        .mmEdit: "Редагування", .mmUndo: "Відмінити", .mmRedo: "Повторити", .mmCut: "Вирізати",
        .mmCopy: "Скопіювати", .mmPaste: "Вставити", .mmSelectAll: "Вибрати все",

        .energyOn: "Mac працює і з закритою кришкою",
        .energyOff: "Закрита кришка присипляє Mac",
        .lidTitle: "Режим закритої кришки",
        .lidOn: "Увімкнено", .lidOff: "Вимкнено", .lidWaiting: "Чекаємо на пароль…", .lidOnFor: "Увімкнено %@",
        .lidExplainOff: "Увімкніть перед тим, як закрити кришку: завантаження, збірки й локальні ШІ-моделі працюватимуть далі. macOS запитає пароль адміністратора.",
        .lidExplainOn: "Системний сон вимкнено, доки ви не вимкнете режим тут, навіть якщо закрити SAVISUL.",
        .batteryConfirmTitle: "Mac працює від батареї",
        .batteryConfirmBody: "Із закритою кришкою Mac працюватиме далі й витрачатиме заряд. Для довгих задач під’єднайте адаптер.",
        .turnOn: "Увімкнути", .cancel: "Скасувати",
        .errCancelled: "Введення пароля скасовано. Нічого не змінилося.",
        .errFailed: "macOS не застосував зміну: %@",
        .errVerify: "Команда виконалася, але параметр сну не змінився. Спробуйте ще раз.",
        .adminPromptOn: "SAVISUL потрібен пароль, щоб Mac не засинав із закритою кришкою.",
        .adminPromptOff: "SAVISUL потрібен пароль, щоб Mac знову міг засинати.",
        .rowPower: "Живлення", .rowIdleSleep: "Сон через бездіяльність", .rowHeldBy: "Не дають заснути",
        .srcBattery: "Батарея", .srcCharging: "Заряджається", .srcAdapter: "Адаптер живлення", .srcNone: "Немає батареї",
        .timeLeft: "залишилось %@", .timeToFull: "до повної %@", .sleepNever: "Ніколи", .sleepAfter: "Через %@",
        .idleTitle: "Не засинати від бездіяльності",
        .idleDetail: "Mac сам не засне, поки кришка відкрита. Пароль не потрібен.",
        .restoredTimers: "Таймери сну повернулися до попередніх значень.",

        .muted: "без звуку", .output: "Вихід", .input: "Вхід", .balance: "Баланс", .centerWord: "Центр",
        .leftShort: "Л", .rightShort: "П", .mute: "Вимкнути звук", .unmute: "Увімкнути звук",
        .fineHint: "Утримуйте ⌥ під час перетягування — крок 0,1 %.",
        .playingNow: "Зараз грає", .silence: "Зараз нічого не грає",
        .noVolume: "Цей пристрій не має регулювання гучності.",
        .wholeDevice: "Рівні задаються для всього пристрою.", .noDevices: "Немає пристроїв",

        .systemSubtitle: "Процесор %@ · Пам’ять %@",
        .processor: "Процесор", .memory: "Пам’ять", .battery: "Батарея", .temperature: "Температура",
        .memoryOf: "%@ з %@",
        .pressureNormal: "Навантаження в нормі", .pressureWarning: "Високе навантаження",
        .pressureCritical: "Критичне навантаження",
        .swapUsed: "Підкачка %@", .healthLine: "Стан %@ · циклів: %@", .chipSensor: "Датчик чипа",
        .busiestApps: "Найактивніші", .measuring: "Вимірюю…",
        .fans: "Вентилятори", .fanName: "Вентилятор %@", .fanStopped: "Зупинено", .fanRange: "%@–%@ об/хв", .fanSpeed: "%@ об/хв", .fansIdle: "Вентилятори стоять",
        .fanNote: "На Apple silicon обертами керує macOS. SAVISUL показує їх наживо й попередить, якщо чип перегріється.",
        .fanNone: "Цей Mac не повідомляє оберти вентиляторів.", .noSensor: "Немає датчика",

        .workSubtitleToday: "%@ у редакторах сьогодні", .workSubtitleWeek: "%@ у редакторах за тиждень",
        .today: "Сьогодні", .sevenDays: "7 днів",
        .inEditors: "У редакторах", .aiApps: "ШІ-застосунки", .typed: "Набрано", .tokensApprox: "≈ Токенів",
        .groupEditors: "Редактори", .groupAssistants: "ШІ-асистенти", .groupOther: "Інші застосунки",
        .showMore: "Показати ще %@", .showLess: "Згорнути",
        .keysTitle: "Рахувати набір тексту",
        .keysBody: "Для підрахунку символів і токенів потрібен дозвіл «Доступність». SAVISUL зберігає лише числа, не текст.",
        .keysWaiting: "Увімкніть SAVISUL у розділі «Доступність». Картка оновиться сама.",
        .keysFailed: "Доступ увімкнено, але macOS не запустив відстеження клавіатури. Перезапустіть SAVISUL.",
        .typingOn: "Набір рахується",
        .allow: "Дозволити", .openSettings: "Відкрити параметри", .reopen: "Перезапустити",
        .workEmpty: "Екранний час з’явиться, коли ви попрацюєте в застосунках. Простій не рахується.",
        .tokenNote: "Токени оцінюються за набраним текстом: приблизно 4 латинські або 2 кириличні символи на токен.",
        .charsTokens: "%@ симв. · ≈%@ токенів",

        .toolsSubtitle: "Зйомка, сповіщення й утиліти",
        .capture: "Зйомка", .capSelection: "Ділянка", .capWindow: "Вікно", .capScreen: "Екран",
        .capRecord: "Запис", .capStop: "Стоп", .capToolbar: "Панель",
        .capSaved: "Збережено й скопійовано в буфер", .videoSaved: "Запис збережено",
        .recordFailed: "Запис не почався. Скористайтеся кнопкою «Панель».", .captureFailed: "Знімок не почався.",
        .lastCapture: "Останній знімок", .revealInFinder: "Показати у Finder", .openFile: "Відкрити",
        .copyAgain: "Копіювати", .copied: "Скопійовано",
        .screenTitle: "Запис екрана",
        .screenBody: "Для зйомки в один клік потрібен доступ до запису екрана. Кнопка «Панель» працює й без нього.",
        .screenAfter: "Увімкніть SAVISUL у параметрах — картка оновиться сама за кілька секунд.",
        .alertsTitle: "Розумні сповіщення", .alertsBody: "Одне сповіщення на подію, потім 15 хвилин тиші.",
        .alertCPU: "Процесор вище", .alertMemory: "Пам’ять вище", .alertBattery: "Батарея нижче",
        .alertHeat: "Чип гарячіший", .alertDone: "Коли важка задача завершиться",
        .alertDoneDetail: "Після 3 і більше хвилин високого навантаження",
        .sendTest: "Перевірити", .notifOff: "Сповіщення для SAVISUL вимкнено.",
        .utilities: "Утиліти", .builtIn: "Вбудовані", .yourUtilities: "Ваші", .addUtility: "Додати",
        .fieldName: "Назва", .fieldTarget: "Шлях до застосунку або команда", .shellCommand: "Команда оболонки",
        .chooseApp: "Обрати застосунок…", .remove: "Видалити",
        .utilitiesEmpty: "Додайте застосунок або команду, якими користуєтеся часто.",
        .uActivity: "Моніторинг", .uTerminal: "Термінал", .uSettings: "Параметри", .uDisk: "Диски",
        .uDisplayOff: "Вимкнути екран", .uCopyIP: "Копіювати IP", .uHidden: "Приховані файли",
        .ipCopied: "Скопійовано: %@", .ipNone: "Немає мережевої адреси",
        .hiddenShown: "Приховані файли видно", .hiddenHidden: "Приховані файли сховано",
        .runDone: "«%@» виконано", .runFailed: "«%@»: помилка — %@", .openFailed: "Не вдалося відкрити «%@»",
        .run: "Запустити",
        .nCPU: "Процесор тримається вище %@ уже хвилину.", .nMemory: "Пам’ять заповнена на %@.",
        .nBattery: "Заряд батареї %@.", .nBatteryLid: "Заряд батареї %@, а режим закритої кришки ввімкнено.",
        .nHeat: "Температура чипа сягнула %@.", .nDone: "Важка задача завершилася через %@.",
        .nTest: "Так виглядають сповіщення SAVISUL.",
        .browserTitle: "Виріз у браузері",
        .browserIdle: "Режим читання, піпетка, лінійка, нотатки, темна тема й скриншоти всієї сторінки в Chrome, Edge, Brave, Arc або Яндекс Браузері, а також керування SAVISUL.",
        .browserConnected: "Працює в %@: кришка, звук і скриншоти з будь-якої вкладки",
        .browserStep1: "Відкрийте сторінку розширень і ввімкніть режим розробника.",
        .browserStep2: "Перетягніть на неї теку Extension.",
        .browserStep3: "Відкрийте будь-який сайт. Виріз на сторінці, нова вкладка лишається звичайною. ⌥⇧N.",
        .browserReveal: "Показати теку",
        .browserOpen: "Розширення",

        .settingsSubtitle: "Версія %@", .language: "Мова", .general: "Основні",
        .openAtLogin: "Відкривати під час входу", .showInDock: "Показувати в Dock", .keepOpen: "Не закривати панель",
        .keepOpenDetail: "Клік повз панель не закриє її",
        .shortcut: "Поєднання клавіш", .shortcutDetail: "Відкриває SAVISUL звідусіль",
        .shortcutBusy: "Це поєднання вже зайняте іншим застосунком",
        .permissions: "Дозволи",
        .permissionsNote: "Статуси оновлюються самі: зміна в Системних параметрах з’явиться тут за кілька секунд.",
        .permAccessibility: "Доступність", .permAccessibilityUse: "Підрахунок набору в «Роботі»",
        .permScreen: "Запис екрана", .permScreenUse: "Знімки й запис в один клік",
        .permNotifications: "Сповіщення", .permNotificationsUse: "Розумні сповіщення",
        .permLogin: "Об’єкт входу", .permLoginUse: "Запуск SAVISUL під час входу",
        .permAdmin: "Адміністратор", .permAdminUse: "Запитується щоразу під час зміни режиму кришки",
        .stAllowed: "Дозволено", .stOff: "Вимкнено", .stNotAsked: "Не запитано", .stApproval: "Чекає схвалення",
        .stAskEachTime: "Щоразу",
        .menuBarHidden: "Рядок меню переповнений, і macOS сховав значок SAVISUL. Утримуйте ⌘ і перетягніть значки, щоб звільнити місце. А поки відкривайте SAVISUL із Dock або поєднанням ⌃⌥S.",
        .dockForced: "Показується, поки значок у рядку меню схований",
        .loginFailed: "macOS не додав об’єкт входу: %@"
    ]

    private static let french: [Copy: String] = [
        .tabEnergy: "Énergie", .tabSound: "Son", .tabSystem: "Système", .tabWork: "Travail", .tabTools: "Outils",
        .tabFeatures: "Fonctions", .featuresSubtitle: "%@ sur %@ activées",
        .tabSettings: "Réglages", .moreMenu: "Plus", .tabAutomations: "Automatisations",
        .menuKeepOpen: "Garder ouvert", .menuDisplayOff: "Éteindre l’écran", .menuScreenshot: "Capture",
        .menuSettings: "Réglages", .menuActivityMonitor: "Moniteur d’activité", .menuQuit: "Quitter SAVISUL",
        .chipAwake: "Éveillé",
        .mmAbout: "À propos de SAVISUL", .mmSettings: "Réglages…", .mmHide: "Masquer SAVISUL",
        .mmQuit: "Quitter SAVISUL", .mmEdit: "Édition", .mmUndo: "Annuler", .mmRedo: "Rétablir",
        .mmCut: "Couper", .mmCopy: "Copier", .mmPaste: "Coller", .mmSelectAll: "Tout sélectionner",

        .energyOn: "Le Mac continue de tourner capot fermé",
        .energyOff: "Fermer le capot met le Mac en veille",
        .lidTitle: "Mode capot fermé",
        .lidOn: "Activé", .lidOff: "Désactivé", .lidWaiting: "En attente du mot de passe…",
        .lidOnFor: "Activé depuis %@",
        .lidExplainOff: "Activez-le avant de fermer le capot : téléchargements, compilations et modèles d’IA locaux continuent. macOS demande le mot de passe administrateur.",
        .lidExplainOn: "La veille système reste coupée jusqu’à ce que vous désactiviez ce mode ici, même si vous quittez SAVISUL.",
        .batteryConfirmTitle: "Le Mac est sur batterie",
        .batteryConfirmBody: "Capot fermé, le Mac continue de travailler et vide la batterie. Branchez l’adaptateur pour les longues tâches.",
        .turnOn: "Activer", .cancel: "Annuler",
        .errCancelled: "Saisie du mot de passe annulée. Rien n’a changé.",
        .errFailed: "macOS n’a pas appliqué la modification : %@",
        .errVerify: "La commande a tourné, mais le réglage de veille n’a pas changé. Réessayez.",
        .adminPromptOn: "SAVISUL a besoin de votre mot de passe pour garder le Mac éveillé capot fermé.",
        .adminPromptOff: "SAVISUL a besoin de votre mot de passe pour réautoriser la veille.",
        .rowPower: "Alimentation", .rowIdleSleep: "Veille d’inactivité", .rowHeldBy: "Maintenu éveillé par",
        .srcBattery: "Batterie", .srcCharging: "En charge", .srcAdapter: "Adaptateur secteur", .srcNone: "Pas de batterie",
        .timeLeft: "%@ restantes", .timeToFull: "pleine dans %@", .sleepNever: "Jamais", .sleepAfter: "Après %@",
        .idleTitle: "Empêcher la veille d’inactivité",
        .idleDetail: "Le Mac reste éveillé tant que le capot est ouvert. Sans mot de passe.",
        .restoredTimers: "Les délais de veille ont retrouvé leurs valeurs précédentes.",

        .muted: "muet", .output: "Sortie", .input: "Entrée", .balance: "Balance", .centerWord: "Centre",
        .leftShort: "G", .rightShort: "D", .mute: "Couper le son", .unmute: "Rétablir le son",
        .fineHint: "Maintenez ⌥ en glissant pour des pas de 0,1 %.",
        .playingNow: "En lecture", .silence: "Rien n’est en lecture",
        .noVolume: "Cet appareil n’a pas de réglage de volume.",
        .wholeDevice: "Les niveaux s’appliquent à tout l’appareil.", .noDevices: "Aucun appareil",

        .systemSubtitle: "Processeur %@ · Mémoire %@",
        .processor: "Processeur", .memory: "Mémoire", .battery: "Batterie", .temperature: "Température",
        .memoryOf: "%@ sur %@",
        .pressureNormal: "Pression normale", .pressureWarning: "Pression élevée", .pressureCritical: "Pression critique",
        .swapUsed: "Swap %@", .healthLine: "Santé %@ · %@ cycles", .chipSensor: "Capteur de la puce",
        .busiestApps: "Apps les plus actives", .measuring: "Mesure en cours…",
        .fans: "Ventilateurs", .fanName: "Ventilateur %@", .fanStopped: "À l’arrêt", .fanRange: "%@–%@ tr/min", .fanSpeed: "%@ tr/min", .fansIdle: "Ventilateurs à l’arrêt",
        .fanNote: "Sur Apple silicon, macOS pilote les ventilateurs. SAVISUL affiche leur vitesse en direct et vous prévient si la puce chauffe.",
        .fanNone: "Ce Mac ne communique pas la vitesse des ventilateurs.", .noSensor: "Pas de capteur",

        .workSubtitleToday: "%@ dans les éditeurs aujourd’hui", .workSubtitleWeek: "%@ dans les éditeurs cette semaine",
        .today: "Aujourd’hui", .sevenDays: "7 jours",
        .inEditors: "Dans les éditeurs", .aiApps: "Apps d’IA", .typed: "Tapé", .tokensApprox: "≈ Jetons",
        .groupEditors: "Éditeurs", .groupAssistants: "Assistants IA", .groupOther: "Autres apps",
        .showMore: "Afficher %@ de plus", .showLess: "Réduire",
        .keysTitle: "Compter la frappe",
        .keysBody: "Les caractères et jetons demandent l’accès Accessibilité. SAVISUL ne garde que des nombres, jamais le texte.",
        .keysWaiting: "Activez SAVISUL dans Accessibilité. Cette carte se met à jour toute seule.",
        .keysFailed: "L’accès est actif, mais macOS n’a pas lancé le suivi du clavier. Relancez SAVISUL.",
        .typingOn: "La frappe est comptée",
        .allow: "Autoriser", .openSettings: "Ouvrir Réglages", .reopen: "Relancer",
        .workEmpty: "Le temps d’écran apparaît ici au fil de votre travail. L’inactivité n’est pas comptée.",
        .tokenNote: "Les jetons sont estimés d’après le texte tapé : environ 4 caractères latins ou 2 cyrilliques par jeton.",
        .charsTokens: "%@ car. · ≈%@ jetons",

        .toolsSubtitle: "Captures, alertes et utilitaires",
        .capture: "Capture", .capSelection: "Sélection", .capWindow: "Fenêtre", .capScreen: "Écran",
        .capRecord: "Filmer", .capStop: "Arrêter", .capToolbar: "Barre",
        .capSaved: "Enregistré et copié dans le presse-papiers", .videoSaved: "Enregistrement sauvegardé",
        .recordFailed: "L’enregistrement n’a pas démarré. Utilisez la Barre.", .captureFailed: "La capture n’a pas démarré.",
        .lastCapture: "Dernière capture", .revealInFinder: "Afficher dans le Finder", .openFile: "Ouvrir",
        .copyAgain: "Copier", .copied: "Copié",
        .screenTitle: "Enregistrement de l’écran",
        .screenBody: "Les captures en un clic demandent l’accès à l’enregistrement de l’écran. La Barre fonctionne sans.",
        .screenAfter: "Activez SAVISUL dans Réglages : cette carte se met à jour seule en quelques secondes.",
        .alertsTitle: "Alertes intelligentes", .alertsBody: "Une notification par événement, puis 15 minutes de calme.",
        .alertCPU: "Processeur au-dessus de", .alertMemory: "Mémoire au-dessus de", .alertBattery: "Batterie sous",
        .alertHeat: "Puce au-dessus de", .alertDone: "Quand une tâche lourde se termine",
        .alertDoneDetail: "Après 3 minutes ou plus de forte charge",
        .sendTest: "Tester", .notifOff: "Les notifications de SAVISUL sont désactivées.",
        .utilities: "Utilitaires", .builtIn: "Inclus", .yourUtilities: "Les vôtres", .addUtility: "Ajouter",
        .fieldName: "Nom", .fieldTarget: "Chemin d’app ou commande", .shellCommand: "Commande shell",
        .chooseApp: "Choisir une app…", .remove: "Retirer",
        .utilitiesEmpty: "Ajoutez une app ou une commande que vous utilisez souvent.",
        .uActivity: "Activité", .uTerminal: "Terminal", .uSettings: "Réglages", .uDisk: "Disques",
        .uDisplayOff: "Écran éteint", .uCopyIP: "Copier l’IP", .uHidden: "Fichiers cachés",
        .ipCopied: "Copié : %@", .ipNone: "Pas d’adresse réseau",
        .hiddenShown: "Fichiers cachés visibles", .hiddenHidden: "Fichiers cachés masqués",
        .runDone: "« %@ » terminé", .runFailed: "« %@ » a échoué : %@", .openFailed: "Impossible d’ouvrir « %@ »",
        .run: "Lancer",
        .nCPU: "Le processeur reste au-dessus de %@ depuis une minute.", .nMemory: "La mémoire est pleine à %@.",
        .nBattery: "La batterie est à %@.", .nBatteryLid: "La batterie est à %@ et le mode capot fermé est actif.",
        .nHeat: "La puce a atteint %@.", .nDone: "La tâche lourde s’est terminée après %@.",
        .nTest: "Voici à quoi ressemblent les alertes SAVISUL.",
        .browserTitle: "Encoche du navigateur",
        .browserIdle: "Lecture, pipette, règle, notes, thème sombre et captures pleine page dans Chrome, Edge, Brave, Arc ou Yandex, avec les commandes SAVISUL.",
        .browserConnected: "Actif dans %@ : capot, son et captures depuis n’importe quel onglet",
        .browserStep1: "Ouvrez la page des extensions et activez le mode développeur.",
        .browserStep2: "Faites glisser le dossier Extension sur cette page.",
        .browserStep3: "Ouvrez un site. L’encoche est sur la page, le nouvel onglet reste celui de Chrome. ⌥⇧N.",
        .browserReveal: "Afficher le dossier",
        .browserOpen: "Extensions",

        .settingsSubtitle: "Version %@", .language: "Langue", .general: "Général",
        .openAtLogin: "Ouvrir à la connexion", .showInDock: "Afficher dans le Dock",
        .keepOpen: "Garder le panneau ouvert", .keepOpenDetail: "Un clic à côté ne le ferme pas",
        .shortcut: "Raccourci", .shortcutDetail: "Ouvre SAVISUL depuis n’importe où",
        .shortcutBusy: "Une autre app utilise déjà ce raccourci",
        .permissions: "Autorisations",
        .permissionsNote: "Mise à jour en direct : un changement dans Réglages Système apparaît ici en quelques secondes.",
        .permAccessibility: "Accessibilité", .permAccessibilityUse: "Compte la frappe dans Travail",
        .permScreen: "Enregistrement de l’écran", .permScreenUse: "Captures et vidéos en un clic",
        .permNotifications: "Notifications", .permNotificationsUse: "Alertes intelligentes",
        .permLogin: "Ouverture à la connexion", .permLoginUse: "Lance SAVISUL à la connexion",
        .permAdmin: "Administrateur", .permAdminUse: "Demandé à chaque changement du mode capot",
        .stAllowed: "Autorisé", .stOff: "Désactivé", .stNotAsked: "Pas demandé", .stApproval: "À approuver",
        .stAskEachTime: "À chaque fois",
        .menuBarHidden: "La barre des menus est pleine : macOS a masqué l’icône SAVISUL. Maintenez ⌘ et faites glisser des icônes pour libérer de la place. En attendant, ouvrez SAVISUL depuis le Dock ou avec ⌃⌥S.",
        .dockForced: "Affiché tant que l’icône de la barre des menus est masquée",
        .loginFailed: "macOS n’a pas ajouté l’ouverture à la connexion : %@"
    ]
}
