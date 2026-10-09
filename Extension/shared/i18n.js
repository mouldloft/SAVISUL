(() => {
  const LANGS = ['en', 'ru', 'uk', 'fr'];
  const NATIVE = { en: 'English', ru: 'Русский', uk: 'Українська', fr: 'Français' };

  const S = {
    en: {
      notchLabel: 'SAVISUL notch', close: 'Close', back: 'Back', done: 'Done', copy: 'Copy', copied: 'Copied',
      copiedValue: 'Copied {0}', download: 'Download', delete: 'Delete', undo: 'Undo', open: 'Open', clear: 'Clear',
      keepOpen: 'Keep open', settings: 'Settings', allSettings: 'All settings', shortcuts: 'Shortcuts',
      escHint: 'Esc to exit',
      secTools: 'Tools', secPage: 'This page', secMac: 'Mac',
      tColor: 'Color', tRuler: 'Ruler', tNote: 'Note', tShot: 'Screenshot', tZap: 'Hide', tFonts: 'Fonts',
      tLink: 'Link · QR', tVideo: 'Video', tImages: 'Images', tReader: 'Reader',
      pDark: 'Dark', pUnlock: 'Free copy', pEdit: 'Edit', pOutline: 'Outlines',

      macLid: 'Closed lid', macAwake: 'Stay awake', macDisplay: 'Display off', macMute: 'Mute', macVolume: 'Volume',
      macBattery: 'Battery {0}', macCharging: 'Charging {0}', macAdapter: 'Power adapter', macCpu: 'CPU {0}',
      macOffline: 'SAVISUL for Mac isn’t running', macLaunch: 'Launch',
      macMissing: 'Open SAVISUL on your Mac once to connect', macConnecting: 'Connecting to SAVISUL…',
      macLidPassword: 'macOS will ask for your password',
      macLidBattery: 'On battery. Keep working with the lid closed?', macTurnOn: 'Turn on', macCancel: 'Cancel',
      macDisplayDone: 'Display is going to sleep', macError: 'SAVISUL didn’t respond', macApp: 'Open SAVISUL',

      noteTitle: 'Note', noteScopePage: 'This page', noteScopeSite: 'Whole site',
      notePlaceholder: 'Write anything. The note stays with this page.',
      notePlaceholderSite: 'Write anything. The note shows on every page of {0}.',
      noteSaved: 'Saved', noteChars: { one: '{0} character', other: '{0} characters' },
      noteDeleted: 'Note deleted', noteHas: 'This page has a note', noteAll: 'All notes',

      colorTitle: 'Color', colorPick: 'Pick a color', colorPicking: 'Click anywhere to pick · Esc to cancel',
      colorRecent: 'Recent', colorContrast: 'Contrast with {0}', colorPalette: 'Page palette',
      colorNoApi: 'This browser has no eyedropper. Update it to the latest version.',
      colorEmpty: 'Pick a color from anywhere on the screen', colorAuto: 'Copy on pick',

      rulerHint: 'Hover to measure · drag for distance · click to pin', rulerClear: 'Clear',
      zapHint: 'Click what you want to hide', zapCount: 'Hidden: {0}', zapRemember: 'Remember for {0}',
      zapRestore: 'Show hidden', zapRestored: 'Hidden elements are back',
      fontsHint: 'Hover text to inspect · click to copy CSS', fontsCopied: 'CSS copied',
      editHint: 'Click any text to change it',
      unlockOn: 'Copying and right-click are unlocked', unlockOff: 'The page’s restrictions are back',
      outlineOn: 'Element outlines on', outlineOff: 'Element outlines off',
      tSpeak: 'Read aloud', speakHint: 'Reading aloud', speakNone: 'Nothing to read here', speakPause: 'Pause',
      speakResume: 'Resume', speakStop: 'Stop', speakRate: 'Speed',
      fSize: 'Size', fWeight: 'Weight', fLine: 'Line height', fTracking: 'Tracking', fStyle: 'Style', fColor: 'Color',
      darkOn: 'Dark theme on for {0}', darkOff: 'Dark theme off for {0}', darkNative: '{0} is already dark',

      readerNone: 'No article found on this page', readerMinutes: '{0} min read', readerSerif: 'Serif',
      readerSans: 'Sans', readerSmaller: 'Smaller', readerLarger: 'Larger', readerWidth: 'Width',
      readerLight: 'Light', readerSepia: 'Sepia', readerDark: 'Dark', readerExit: 'Exit reader',

      shotTitle: 'Screenshot', shotFull: 'Full page', shotFullDetail: 'Scrolls and stitches the whole page',
      shotVisible: 'Visible area', shotVisibleDetail: 'What you see right now', shotRegion: 'Region',
      shotRegionDetail: 'Drag to select part of the page', shotWorking: 'Capturing… {0}',
      shotRegionHint: 'Drag to select · Esc to cancel', shotFailed: 'This page can’t be captured',
      shotBusy: 'Another capture is running', shotTabChanged: 'Capture stopped: the tab changed',

      capTitle: 'Screenshot', capPng: 'Download PNG', capJpg: 'JPEG', capCopy: 'Copy',
      capCopied: 'Copied to the clipboard', capSave: 'Save to SAVISUL', capSaved: 'Saved to Pictures › SAVISUL',
      capReveal: 'Show in Finder', capDownloaded: 'Saved to Downloads › SAVISUL',
      capParts: 'The page is very tall, so the capture is split into {0} parts', capSize: '{0} × {1} px',
      capLoading: 'Stitching…', capMissing: 'This screenshot is no longer available',
      capMacOffline: 'Open SAVISUL on your Mac to save here', capFailed: 'Couldn’t save the file',

      linkTitle: 'Link', linkClean: 'Clean link', linkRemoved: 'Removed trackers: {0}',
      linkNoTrackers: 'No trackers in this link', linkMarkdown: 'Markdown', linkTitleCopy: 'Title',
      linkQr: 'Scan with your phone camera', linkSaveQr: 'Save QR', linkTooLong: 'Too long for a QR code',

      videoTitle: 'Video', videoNone: 'No video on this page', videoSpeed: 'Speed', videoPip: 'Picture in picture',
      videoLoop: 'Loop', videoKeep: 'Keep speed on {0}', videoMany: 'Videos on the page: {0}',

      imagesTitle: 'Images on this page', imagesCount: { one: '{0} image', other: '{0} images' },
      imagesSmall: 'Hide small', imagesAll: 'Download all', imagesNone: 'No images found',
      imagesStarted: 'Downloading {0}',

      setLanguage: 'Language', setAuto: 'Auto', setPosition: 'Position', posLeft: 'Left', posCenter: 'Center',
      posRight: 'Right', setIdle: 'At rest', idleNotch: 'Notch', idleLine: 'Line', idleHidden: 'Hidden',
      setTheme: 'Theme', themeDark: 'Dark', themeLight: 'Light', setHover: 'Open on hover',
      setHideSite: 'Hide on {0}', setHidden: 'The notch is hidden on {0}. ⌥⇧N still opens it.',

      optTitle: 'SAVISUL for your browser', optSubtitle: 'The notch that ships with SAVISUL for Mac',
      optGeneral: 'Notch', optNotes: 'Notes', optNotesEmpty: 'Notes you write in the notch show up here.',
      optSearch: 'Search notes', optExport: 'Export', optHidden: 'Hidden elements',
      optHiddenEmpty: 'Elements you hide and remember show up here.', optDark: 'Dark theme',
      optDarkAll: 'Dark theme on every site', optDarkAllDetail: 'Sites that are already dark stay as they are.',
      optDarkSites: 'Sites', optDarkEmpty: 'Turn on dark theme for a site from the notch (⌥⇧D).',
      darkStateOn: 'Dark', darkStateOff: 'Original',
      optMac: 'SAVISUL for Mac', optMacConnected: 'Connected · SAVISUL {0}', optMacOffline: 'The app isn’t running',
      optMacMissing: 'Not connected. Open SAVISUL on your Mac once.',
      optMacDetail: 'While SAVISUL runs, the notch controls closed-lid mode, sleep and volume, shows battery and CPU, and saves screenshots straight to Pictures › SAVISUL.',
      optShortcuts: 'Shortcuts', optShortcutsChange: 'Change shortcuts', optNotSet: 'Not set',
      optAbout: 'About', optVersion: 'Version {0}', optWelcomeTitle: 'SAVISUL is in your browser',
      optWelcomeBody: 'Move the pointer to the top of any page or press ⌥⇧N. Reload tabs that were already open.',
      optClearAll: 'Delete all', optConfirmDelete: 'Delete all notes?', optSitePage: 'Page', optSiteWide: 'Site',
      optRules: { one: '{0} rule', other: '{0} rules' }, optTools: 'What’s in the notch', optOpenNotch: 'opens the notch on any page',

      dReader: 'Just the text, without ads and clutter', dColor: 'Any color on screen in HEX, RGB, HSL, with a contrast check',
      dRuler: 'Element sizes, spacing and distances', dNote: 'A note tied to the page or the whole site',
      dDark: 'Dark theme for any site, remembered per site', dShot: 'Full page, visible area or a region',
      dZap: 'Hide banners and popups, even on the next visit', dFonts: 'Font, size, weight and color of any text',
      dLink: 'A link without trackers, Markdown and a QR code', dVideo: 'Speed up to 4×, picture in picture, loop',
      dImages: 'Every image on the page, with sizes and downloads', dUnlock: 'Copy and right-click where sites block them',
      dEdit: 'Change any text on the page before a screenshot', dOutline: 'Outline every element to see the layout',
      dSpeak: 'Reads the article or the selected text aloud', dMac: 'Closed lid, sleep, volume and battery of your Mac',

      restricted: 'The browser doesn’t allow extensions on this page',
      reloadNeeded: 'Reload the page to use SAVISUL here'
    },

    ru: {
      notchLabel: 'Чёлка SAVISUL', close: 'Закрыть', back: 'Назад', done: 'Готово', copy: 'Копировать',
      copied: 'Скопировано', copiedValue: 'Скопировано: {0}', download: 'Скачать', delete: 'Удалить',
      undo: 'Отменить', open: 'Открыть', clear: 'Очистить', keepOpen: 'Не закрывать', settings: 'Настройки',
      allSettings: 'Все настройки', shortcuts: 'Сочетания клавиш', escHint: 'Esc — выход',
      secTools: 'Инструменты', secPage: 'Эта страница', secMac: 'Mac',
      tColor: 'Пипетка', tRuler: 'Линейка', tNote: 'Заметка', tShot: 'Скриншот', tZap: 'Скрыть', tFonts: 'Шрифты',
      tLink: 'Ссылка · QR', tVideo: 'Видео', tImages: 'Картинки', tReader: 'Чтение',
      pDark: 'Тёмная', pUnlock: 'Копирование', pEdit: 'Правка', pOutline: 'Контуры',

      macLid: 'Закрытая крышка', macAwake: 'Не спать', macDisplay: 'Погасить экран', macMute: 'Без звука',
      macVolume: 'Громкость', macBattery: 'Батарея {0}', macCharging: 'Заряжается {0}', macAdapter: 'От сети',
      macCpu: 'ЦП {0}', macOffline: 'SAVISUL для Mac не запущен', macLaunch: 'Запустить',
      macMissing: 'Откройте SAVISUL на Mac один раз — и они свяжутся', macConnecting: 'Подключаюсь к SAVISUL…',
      macLidPassword: 'macOS попросит пароль',
      macLidBattery: 'Mac работает от батареи. Включить режим закрытой крышки?', macTurnOn: 'Включить',
      macCancel: 'Отмена', macDisplayDone: 'Экран гаснет', macError: 'SAVISUL не ответил', macApp: 'Открыть SAVISUL',

      noteTitle: 'Заметка', noteScopePage: 'Эта страница', noteScopeSite: 'Весь сайт',
      notePlaceholder: 'Пишите что угодно — заметка останется у этой страницы.',
      notePlaceholderSite: 'Пишите что угодно — заметка будет на всех страницах {0}.',
      noteSaved: 'Сохранено', noteChars: { one: '{0} символ', few: '{0} символа', many: '{0} символов', other: '{0} символа' },
      noteDeleted: 'Заметка удалена', noteHas: 'У страницы есть заметка', noteAll: 'Все заметки',

      colorTitle: 'Цвет', colorPick: 'Выбрать цвет', colorPicking: 'Нажмите в любом месте · Esc — отмена',
      colorRecent: 'Недавние', colorContrast: 'Контраст с {0}', colorPalette: 'Палитра страницы',
      colorNoApi: 'В этом браузере нет пипетки. Обновите его до последней версии.',
      colorEmpty: 'Возьмите цвет из любой точки экрана', colorAuto: 'Копировать сразу',

      rulerHint: 'Наведите — размеры · тяните — расстояние · клик — закрепить', rulerClear: 'Очистить',
      zapHint: 'Нажмите на то, что хотите скрыть', zapCount: 'Скрыто: {0}', zapRemember: 'Запомнить для {0}',
      zapRestore: 'Вернуть скрытое', zapRestored: 'Скрытые элементы возвращены',
      fontsHint: 'Наведите на текст · клик — скопировать CSS', fontsCopied: 'CSS скопирован',
      editHint: 'Нажмите на любой текст, чтобы изменить его',
      unlockOn: 'Копирование и правый клик разблокированы', unlockOff: 'Ограничения страницы возвращены',
      outlineOn: 'Контуры элементов включены', outlineOff: 'Контуры элементов выключены',
      tSpeak: 'Озвучить', speakHint: 'Читаю вслух', speakNone: 'Здесь нечего читать', speakPause: 'Пауза',
      speakResume: 'Дальше', speakStop: 'Стоп', speakRate: 'Скорость',
      fSize: 'Размер', fWeight: 'Насыщенность', fLine: 'Интерлиньяж', fTracking: 'Трекинг', fStyle: 'Начертание', fColor: 'Цвет',
      darkOn: 'Тёмная тема для {0}', darkOff: 'Тёмная тема выключена для {0}', darkNative: '{0} уже тёмный',

      readerNone: 'На этой странице не нашлось статьи', readerMinutes: '{0} мин чтения', readerSerif: 'С засечками',
      readerSans: 'Без засечек', readerSmaller: 'Мельче', readerLarger: 'Крупнее', readerWidth: 'Ширина',
      readerLight: 'Светлая', readerSepia: 'Сепия', readerDark: 'Тёмная', readerExit: 'Закрыть чтение',

      shotTitle: 'Скриншот', shotFull: 'Вся страница', shotFullDetail: 'Прокрутит и склеит всю страницу',
      shotVisible: 'Видимая часть', shotVisibleDetail: 'То, что сейчас на экране', shotRegion: 'Область',
      shotRegionDetail: 'Выделите часть страницы', shotWorking: 'Снимаю… {0}',
      shotRegionHint: 'Выделите область · Esc — отмена', shotFailed: 'Эту страницу нельзя снять',
      shotBusy: 'Съёмка уже идёт', shotTabChanged: 'Съёмка остановлена: сменилась вкладка',

      capTitle: 'Скриншот', capPng: 'Скачать PNG', capJpg: 'JPEG', capCopy: 'Копировать',
      capCopied: 'Скопировано в буфер обмена', capSave: 'Сохранить в SAVISUL', capSaved: 'Сохранено в «Изображения › SAVISUL»',
      capReveal: 'Показать в Finder', capDownloaded: 'Сохранено в «Загрузки › SAVISUL»',
      capParts: 'Страница очень длинная, поэтому снимок разбит на части: {0}', capSize: '{0} × {1} пкс',
      capLoading: 'Склеиваю…', capMissing: 'Этот снимок больше недоступен',
      capMacOffline: 'Откройте SAVISUL на Mac, чтобы сохранять сюда', capFailed: 'Не удалось сохранить файл',

      linkTitle: 'Ссылка', linkClean: 'Чистая ссылка', linkRemoved: 'Удалено трекеров: {0}',
      linkNoTrackers: 'В ссылке нет трекеров', linkMarkdown: 'Markdown', linkTitleCopy: 'Заголовок',
      linkQr: 'Наведите камеру телефона', linkSaveQr: 'Сохранить QR', linkTooLong: 'Слишком длинная для QR-кода',

      videoTitle: 'Видео', videoNone: 'На странице нет видео', videoSpeed: 'Скорость', videoPip: 'Картинка в картинке',
      videoLoop: 'Повтор', videoKeep: 'Держать скорость на {0}', videoMany: 'Видео на странице: {0}',

      imagesTitle: 'Картинки на странице',
      imagesCount: { one: '{0} картинка', few: '{0} картинки', many: '{0} картинок', other: '{0} картинки' },
      imagesSmall: 'Без мелких', imagesAll: 'Скачать все', imagesNone: 'Картинок не нашлось', imagesStarted: 'Скачиваю: {0}',

      setLanguage: 'Язык', setAuto: 'Авто', setPosition: 'Положение', posLeft: 'Слева', posCenter: 'По центру',
      posRight: 'Справа', setIdle: 'В покое', idleNotch: 'Чёлка', idleLine: 'Линия', idleHidden: 'Скрыта',
      setTheme: 'Тема', themeDark: 'Тёмная', themeLight: 'Светлая', setHover: 'Открывать наведением',
      setHideSite: 'Не показывать на {0}', setHidden: 'Чёлка скрыта на {0}. ⌥⇧N всё равно откроет её.',

      optTitle: 'SAVISUL для браузера', optSubtitle: 'Чёлка, которая идёт вместе с SAVISUL для Mac',
      optGeneral: 'Чёлка', optNotes: 'Заметки', optNotesEmpty: 'Здесь появятся заметки, которые вы пишете в чёлке.',
      optSearch: 'Поиск по заметкам', optExport: 'Экспорт', optHidden: 'Скрытые элементы',
      optHiddenEmpty: 'Здесь появятся элементы, которые вы скрыли и запомнили.', optDark: 'Тёмная тема',
      optDarkAll: 'Тёмная тема на всех сайтах', optDarkAllDetail: 'Сайты, которые уже тёмные, не меняются.',
      optDarkSites: 'Сайты', optDarkEmpty: 'Включите тёмную тему для сайта из чёлки (⌥⇧D).',
      darkStateOn: 'Тёмная', darkStateOff: 'Оригинал',
      optMac: 'SAVISUL для Mac', optMacConnected: 'Подключено · SAVISUL {0}', optMacOffline: 'Приложение не запущено',
      optMacMissing: 'Не подключено. Откройте SAVISUL на Mac один раз.',
      optMacDetail: 'Пока SAVISUL запущен, из чёлки можно управлять закрытой крышкой, сном и громкостью, видеть батарею и процессор, а скриншоты сохранять прямо в «Изображения › SAVISUL».',
      optShortcuts: 'Сочетания клавиш', optShortcutsChange: 'Изменить сочетания', optNotSet: 'Не задано',
      optAbout: 'О расширении', optVersion: 'Версия {0}', optWelcomeTitle: 'SAVISUL теперь в браузере',
      optWelcomeBody: 'Наведите указатель на верх любой страницы или нажмите ⌥⇧N. Уже открытые вкладки нужно обновить.',
      optClearAll: 'Удалить все', optConfirmDelete: 'Удалить все заметки?', optSitePage: 'Страница', optSiteWide: 'Сайт',
      optRules: { one: '{0} правило', few: '{0} правила', many: '{0} правил', other: '{0} правила' },
      optTools: 'Что есть в чёлке', optOpenNotch: 'открывает чёлку на любой странице',

      dReader: 'Только текст — без рекламы и мусора', dColor: 'Любой цвет с экрана в HEX, RGB, HSL и проверка контраста',
      dRuler: 'Размеры элементов, отступы и расстояния', dNote: 'Заметка, привязанная к странице или сайту',
      dDark: 'Тёмная тема для любого сайта, запоминается', dShot: 'Вся страница, видимая часть или область',
      dZap: 'Скрывает баннеры и попапы — даже при следующем визите', dFonts: 'Шрифт, размер, насыщенность и цвет любого текста',
      dLink: 'Ссылка без трекеров, Markdown и QR-код', dVideo: 'Скорость до 4×, картинка в картинке, повтор',
      dImages: 'Все картинки страницы с размерами и скачиванием', dUnlock: 'Копирование и правый клик там, где сайт их запретил',
      dEdit: 'Меняйте любой текст на странице перед скриншотом', dOutline: 'Контуры всех элементов — видна вёрстка',
      dSpeak: 'Прочитает вслух статью или выделенный текст', dMac: 'Закрытая крышка, сон, громкость и батарея вашего Mac',

      restricted: 'Браузер не разрешает расширения на этой странице',
      reloadNeeded: 'Обновите страницу, чтобы пользоваться SAVISUL'
    },

    uk: {
      notchLabel: 'Виріз SAVISUL', close: 'Закрити', back: 'Назад', done: 'Готово', copy: 'Копіювати',
      copied: 'Скопійовано', copiedValue: 'Скопійовано: {0}', download: 'Завантажити', delete: 'Видалити',
      undo: 'Скасувати', open: 'Відкрити', clear: 'Очистити', keepOpen: 'Не закривати', settings: 'Налаштування',
      allSettings: 'Усі налаштування', shortcuts: 'Комбінації клавіш', escHint: 'Esc — вихід',
      secTools: 'Інструменти', secPage: 'Ця сторінка', secMac: 'Mac',
      tColor: 'Піпетка', tRuler: 'Лінійка', tNote: 'Нотатка', tShot: 'Скриншот', tZap: 'Сховати', tFonts: 'Шрифти',
      tLink: 'URL · QR', tVideo: 'Відео', tImages: 'Зображення', tReader: 'Читання',
      pDark: 'Темна', pUnlock: 'Копіювання', pEdit: 'Редагування', pOutline: 'Контури',

      macLid: 'Закрита кришка', macAwake: 'Не спати', macDisplay: 'Вимкнути екран', macMute: 'Без звуку',
      macVolume: 'Гучність', macBattery: 'Батарея {0}', macCharging: 'Заряджається {0}', macAdapter: 'Від мережі',
      macCpu: 'ЦП {0}', macOffline: 'SAVISUL для Mac не запущено', macLaunch: 'Запустити',
      macMissing: 'Відкрийте SAVISUL на Mac один раз — і вони з’єднаються', macConnecting: 'Під’єднуюся до SAVISUL…',
      macLidPassword: 'macOS попросить пароль',
      macLidBattery: 'Mac працює від батареї. Увімкнути режим закритої кришки?', macTurnOn: 'Увімкнути',
      macCancel: 'Скасувати', macDisplayDone: 'Екран гасне', macError: 'SAVISUL не відповів', macApp: 'Відкрити SAVISUL',

      noteTitle: 'Нотатка', noteScopePage: 'Ця сторінка', noteScopeSite: 'Увесь сайт',
      notePlaceholder: 'Пишіть що завгодно — нотатка залишиться в цієї сторінки.',
      notePlaceholderSite: 'Пишіть що завгодно — нотатка буде на всіх сторінках {0}.',
      noteSaved: 'Збережено', noteChars: { one: '{0} символ', few: '{0} символи', many: '{0} символів', other: '{0} символу' },
      noteDeleted: 'Нотатку видалено', noteHas: 'Сторінка має нотатку', noteAll: 'Усі нотатки',

      colorTitle: 'Колір', colorPick: 'Вибрати колір', colorPicking: 'Натисніть будь-де · Esc — скасувати',
      colorRecent: 'Нещодавні', colorContrast: 'Контраст із {0}', colorPalette: 'Палітра сторінки',
      colorNoApi: 'У цьому браузері немає піпетки. Оновіть його до останньої версії.',
      colorEmpty: 'Візьміть колір з будь-якої точки екрана', colorAuto: 'Копіювати одразу',

      rulerHint: 'Наведіть — розміри · тягніть — відстань · клік — закріпити', rulerClear: 'Очистити',
      zapHint: 'Натисніть на те, що хочете сховати', zapCount: 'Сховано: {0}', zapRemember: 'Запам’ятати для {0}',
      zapRestore: 'Повернути сховане', zapRestored: 'Сховані елементи повернуто',
      fontsHint: 'Наведіть на текст · клік — скопіювати CSS', fontsCopied: 'CSS скопійовано',
      editHint: 'Натисніть на будь-який текст, щоб змінити його',
      unlockOn: 'Копіювання та правий клік розблоковано', unlockOff: 'Обмеження сторінки повернуто',
      outlineOn: 'Контури елементів увімкнено', outlineOff: 'Контури елементів вимкнено',
      tSpeak: 'Озвучити', speakHint: 'Читаю вголос', speakNone: 'Тут нічого читати', speakPause: 'Пауза',
      speakResume: 'Далі', speakStop: 'Стоп', speakRate: 'Швидкість',
      fSize: 'Розмір', fWeight: 'Насиченість', fLine: 'Інтерліньяж', fTracking: 'Трекінг', fStyle: 'Накреслення', fColor: 'Колір',
      darkOn: 'Темна тема для {0}', darkOff: 'Темну тему вимкнено для {0}', darkNative: '{0} уже темний',

      readerNone: 'На цій сторінці не знайшлося статті', readerMinutes: '{0} хв читання', readerSerif: 'Із зарубками',
      readerSans: 'Без зарубок', readerSmaller: 'Дрібніше', readerLarger: 'Більше', readerWidth: 'Ширина',
      readerLight: 'Світла', readerSepia: 'Сепія', readerDark: 'Темна', readerExit: 'Закрити читання',

      shotTitle: 'Скриншот', shotFull: 'Уся сторінка', shotFullDetail: 'Прокрутить і склеїть усю сторінку',
      shotVisible: 'Видима частина', shotVisibleDetail: 'Те, що зараз на екрані', shotRegion: 'Область',
      shotRegionDetail: 'Виділіть частину сторінки', shotWorking: 'Знімаю… {0}',
      shotRegionHint: 'Виділіть область · Esc — скасувати', shotFailed: 'Цю сторінку не можна зняти',
      shotBusy: 'Зйомка вже триває', shotTabChanged: 'Зйомку зупинено: змінилася вкладка',

      capTitle: 'Скриншот', capPng: 'Завантажити PNG', capJpg: 'JPEG', capCopy: 'Копіювати',
      capCopied: 'Скопійовано в буфер обміну', capSave: 'Зберегти в SAVISUL', capSaved: 'Збережено в «Зображення › SAVISUL»',
      capReveal: 'Показати у Finder', capDownloaded: 'Збережено в «Завантаження › SAVISUL»',
      capParts: 'Сторінка дуже довга, тому знімок поділено на частини: {0}', capSize: '{0} × {1} пкс',
      capLoading: 'Склеюю…', capMissing: 'Цей знімок більше недоступний',
      capMacOffline: 'Відкрийте SAVISUL на Mac, щоб зберігати сюди', capFailed: 'Не вдалося зберегти файл',

      linkTitle: 'Посилання', linkClean: 'Чисте посилання', linkRemoved: 'Видалено трекерів: {0}',
      linkNoTrackers: 'У посиланні немає трекерів', linkMarkdown: 'Markdown', linkTitleCopy: 'Заголовок',
      linkQr: 'Наведіть камеру телефона', linkSaveQr: 'Зберегти QR', linkTooLong: 'Задовге для QR-коду',

      videoTitle: 'Відео', videoNone: 'На сторінці немає відео', videoSpeed: 'Швидкість', videoPip: 'Картинка в картинці',
      videoLoop: 'Повтор', videoKeep: 'Тримати швидкість на {0}', videoMany: 'Відео на сторінці: {0}',

      imagesTitle: 'Зображення на сторінці',
      imagesCount: { one: '{0} зображення', few: '{0} зображення', many: '{0} зображень', other: '{0} зображення' },
      imagesSmall: 'Без дрібних', imagesAll: 'Завантажити все', imagesNone: 'Зображень не знайдено',
      imagesStarted: 'Завантажую: {0}',

      setLanguage: 'Мова', setAuto: 'Авто', setPosition: 'Положення', posLeft: 'Ліворуч', posCenter: 'По центру',
      posRight: 'Праворуч', setIdle: 'У спокої', idleNotch: 'Виріз', idleLine: 'Лінія', idleHidden: 'Прихований',
      setTheme: 'Тема', themeDark: 'Темна', themeLight: 'Світла', setHover: 'Відкривати наведенням',
      setHideSite: 'Не показувати на {0}', setHidden: 'Виріз приховано на {0}. ⌥⇧N однаково відкриє його.',

      optTitle: 'SAVISUL для браузера', optSubtitle: 'Виріз, що постачається разом із SAVISUL для Mac',
      optGeneral: 'Виріз', optNotes: 'Нотатки', optNotesEmpty: 'Тут з’являться нотатки, які ви пишете у вирізі.',
      optSearch: 'Пошук у нотатках', optExport: 'Експорт', optHidden: 'Сховані елементи',
      optHiddenEmpty: 'Тут з’являться елементи, які ви сховали й запам’ятали.', optDark: 'Темна тема',
      optDarkAll: 'Темна тема на всіх сайтах', optDarkAllDetail: 'Сайти, які вже темні, не змінюються.',
      optDarkSites: 'Сайти', optDarkEmpty: 'Увімкніть темну тему для сайту з вирізу (⌥⇧D).',
      darkStateOn: 'Темна', darkStateOff: 'Оригінал',
      optMac: 'SAVISUL для Mac', optMacConnected: 'Підключено · SAVISUL {0}', optMacOffline: 'Застосунок не запущено',
      optMacMissing: 'Не підключено. Відкрийте SAVISUL на Mac один раз.',
      optMacDetail: 'Поки SAVISUL запущено, з вирізу можна керувати закритою кришкою, сном і гучністю, бачити батарею й процесор, а скриншоти зберігати просто в «Зображення › SAVISUL».',
      optShortcuts: 'Комбінації клавіш', optShortcutsChange: 'Змінити комбінації', optNotSet: 'Не задано',
      optAbout: 'Про розширення', optVersion: 'Версія {0}', optWelcomeTitle: 'SAVISUL тепер у браузері',
      optWelcomeBody: 'Наведіть вказівник на верх будь-якої сторінки або натисніть ⌥⇧N. Уже відкриті вкладки треба оновити.',
      optClearAll: 'Видалити все', optConfirmDelete: 'Видалити всі нотатки?', optSitePage: 'Сторінка', optSiteWide: 'Сайт',
      optRules: { one: '{0} правило', few: '{0} правила', many: '{0} правил', other: '{0} правила' },
      optTools: 'Що є у вирізі', optOpenNotch: 'відкриває виріз на будь-якій сторінці',

      dReader: 'Лише текст — без реклами й сміття', dColor: 'Будь-який колір з екрана в HEX, RGB, HSL і перевірка контрасту',
      dRuler: 'Розміри елементів, відступи й відстані', dNote: 'Нотатка, прив’язана до сторінки або сайту',
      dDark: 'Темна тема для будь-якого сайту, запам’ятовується', dShot: 'Уся сторінка, видима частина або область',
      dZap: 'Ховає банери й попапи — навіть під час наступного візиту', dFonts: 'Шрифт, розмір, насиченість і колір будь-якого тексту',
      dLink: 'Посилання без трекерів, Markdown і QR-код', dVideo: 'Швидкість до 4×, картинка в картинці, повтор',
      dImages: 'Усі зображення сторінки з розмірами й завантаженням', dUnlock: 'Копіювання та правий клік там, де сайт їх заборонив',
      dEdit: 'Змінюйте будь-який текст на сторінці перед скриншотом', dOutline: 'Контури всіх елементів — видно верстку',
      dSpeak: 'Прочитає вголос статтю або виділений текст', dMac: 'Закрита кришка, сон, гучність і батарея вашого Mac',

      restricted: 'Браузер не дозволяє розширення на цій сторінці',
      reloadNeeded: 'Оновіть сторінку, щоб користуватися SAVISUL'
    },

    fr: {
      notchLabel: 'Encoche SAVISUL', close: 'Fermer', back: 'Retour', done: 'Terminé', copy: 'Copier', copied: 'Copié',
      copiedValue: 'Copié : {0}', download: 'Télécharger', delete: 'Supprimer', undo: 'Annuler', open: 'Ouvrir',
      clear: 'Effacer', keepOpen: 'Garder ouvert', settings: 'Réglages', allSettings: 'Tous les réglages',
      shortcuts: 'Raccourcis', escHint: 'Échap pour quitter',
      secTools: 'Outils', secPage: 'Cette page', secMac: 'Mac',
      tColor: 'Pipette', tRuler: 'Règle', tNote: 'Note', tShot: 'Capture', tZap: 'Masquer', tFonts: 'Polices',
      tLink: 'Lien · QR', tVideo: 'Vidéo', tImages: 'Images', tReader: 'Lecture',
      pDark: 'Sombre', pUnlock: 'Copie libre', pEdit: 'Édition', pOutline: 'Contours',

      macLid: 'Capot fermé', macAwake: 'Rester éveillé', macDisplay: 'Éteindre l’écran', macMute: 'Muet',
      macVolume: 'Volume', macBattery: 'Batterie {0}', macCharging: 'En charge {0}', macAdapter: 'Sur secteur',
      macCpu: 'CPU {0}', macOffline: 'SAVISUL pour Mac n’est pas lancé', macLaunch: 'Lancer',
      macMissing: 'Ouvrez SAVISUL sur votre Mac une fois pour les relier', macConnecting: 'Connexion à SAVISUL…',
      macLidPassword: 'macOS demandera votre mot de passe',
      macLidBattery: 'Sur batterie. Activer le mode capot fermé ?', macTurnOn: 'Activer', macCancel: 'Annuler',
      macDisplayDone: 'L’écran se met en veille', macError: 'SAVISUL n’a pas répondu', macApp: 'Ouvrir SAVISUL',

      noteTitle: 'Note', noteScopePage: 'Cette page', noteScopeSite: 'Tout le site',
      notePlaceholder: 'Écrivez ce que vous voulez : la note reste attachée à cette page.',
      notePlaceholderSite: 'Écrivez ce que vous voulez : la note s’affiche sur toutes les pages de {0}.',
      noteSaved: 'Enregistré', noteChars: { one: '{0} caractère', other: '{0} caractères' },
      noteDeleted: 'Note supprimée', noteHas: 'Cette page a une note', noteAll: 'Toutes les notes',

      colorTitle: 'Couleur', colorPick: 'Choisir une couleur', colorPicking: 'Cliquez n’importe où · Échap pour annuler',
      colorRecent: 'Récentes', colorContrast: 'Contraste avec {0}', colorPalette: 'Palette de la page',
      colorNoApi: 'Ce navigateur n’a pas de pipette. Mettez-le à jour.',
      colorEmpty: 'Prélevez une couleur n’importe où à l’écran', colorAuto: 'Copier au choix',

      rulerHint: 'Survolez pour mesurer · glissez pour une distance · cliquez pour épingler', rulerClear: 'Effacer',
      zapHint: 'Cliquez sur ce que vous voulez masquer', zapCount: 'Masqués : {0}', zapRemember: 'Mémoriser pour {0}',
      zapRestore: 'Réafficher', zapRestored: 'Les éléments masqués sont de retour',
      fontsHint: 'Survolez un texte · cliquez pour copier le CSS', fontsCopied: 'CSS copié',
      editHint: 'Cliquez sur un texte pour le modifier',
      unlockOn: 'Copie et clic droit débloqués', unlockOff: 'Les restrictions de la page sont rétablies',
      outlineOn: 'Contours des éléments activés', outlineOff: 'Contours des éléments désactivés',
      tSpeak: 'Écouter', speakHint: 'Lecture à voix haute', speakNone: 'Rien à lire ici', speakPause: 'Pause',
      speakResume: 'Reprendre', speakStop: 'Arrêter', speakRate: 'Vitesse',
      fSize: 'Taille', fWeight: 'Graisse', fLine: 'Interligne', fTracking: 'Approche', fStyle: 'Style', fColor: 'Couleur',
      darkOn: 'Thème sombre pour {0}', darkOff: 'Thème sombre désactivé pour {0}', darkNative: '{0} est déjà sombre',

      readerNone: 'Aucun article trouvé sur cette page', readerMinutes: '{0} min de lecture', readerSerif: 'Avec empattements',
      readerSans: 'Sans empattements', readerSmaller: 'Plus petit', readerLarger: 'Plus grand', readerWidth: 'Largeur',
      readerLight: 'Clair', readerSepia: 'Sépia', readerDark: 'Sombre', readerExit: 'Quitter la lecture',

      shotTitle: 'Capture d’écran', shotFull: 'Page entière', shotFullDetail: 'Fait défiler et assemble toute la page',
      shotVisible: 'Zone visible', shotVisibleDetail: 'Ce que vous voyez maintenant', shotRegion: 'Zone',
      shotRegionDetail: 'Sélectionnez une partie de la page', shotWorking: 'Capture… {0}',
      shotRegionHint: 'Glissez pour sélectionner · Échap pour annuler', shotFailed: 'Cette page ne peut pas être capturée',
      shotBusy: 'Une capture est déjà en cours', shotTabChanged: 'Capture arrêtée : l’onglet a changé',

      capTitle: 'Capture d’écran', capPng: 'Télécharger PNG', capJpg: 'JPEG', capCopy: 'Copier',
      capCopied: 'Copié dans le presse-papiers', capSave: 'Enregistrer dans SAVISUL', capSaved: 'Enregistré dans Images › SAVISUL',
      capReveal: 'Afficher dans le Finder', capDownloaded: 'Enregistré dans Téléchargements › SAVISUL',
      capParts: 'La page est très longue : la capture est divisée en {0} parties', capSize: '{0} × {1} px',
      capLoading: 'Assemblage…', capMissing: 'Cette capture n’est plus disponible',
      capMacOffline: 'Ouvrez SAVISUL sur votre Mac pour enregistrer ici', capFailed: 'Impossible d’enregistrer le fichier',

      linkTitle: 'Lien', linkClean: 'Lien propre', linkRemoved: 'Traceurs retirés : {0}',
      linkNoTrackers: 'Aucun traceur dans ce lien', linkMarkdown: 'Markdown', linkTitleCopy: 'Titre',
      linkQr: 'Scannez avec l’appareil photo du téléphone', linkSaveQr: 'Enregistrer le QR', linkTooLong: 'Trop long pour un QR code',

      videoTitle: 'Vidéo', videoNone: 'Aucune vidéo sur cette page', videoSpeed: 'Vitesse', videoPip: 'Image dans l’image',
      videoLoop: 'Boucle', videoKeep: 'Garder la vitesse sur {0}', videoMany: 'Vidéos sur la page : {0}',

      imagesTitle: 'Images de la page', imagesCount: { one: '{0} image', other: '{0} images' },
      imagesSmall: 'Sans les petites', imagesAll: 'Tout télécharger', imagesNone: 'Aucune image trouvée',
      imagesStarted: 'Téléchargement : {0}',

      setLanguage: 'Langue', setAuto: 'Auto', setPosition: 'Position', posLeft: 'Gauche', posCenter: 'Centre',
      posRight: 'Droite', setIdle: 'Au repos', idleNotch: 'Encoche', idleLine: 'Ligne', idleHidden: 'Masquée',
      setTheme: 'Thème', themeDark: 'Sombre', themeLight: 'Clair', setHover: 'Ouvrir au survol',
      setHideSite: 'Masquer sur {0}', setHidden: 'L’encoche est masquée sur {0}. ⌥⇧N l’ouvre quand même.',

      optTitle: 'SAVISUL pour le navigateur', optSubtitle: 'L’encoche fournie avec SAVISUL pour Mac',
      optGeneral: 'Encoche', optNotes: 'Notes', optNotesEmpty: 'Les notes écrites dans l’encoche apparaissent ici.',
      optSearch: 'Rechercher dans les notes', optExport: 'Exporter', optHidden: 'Éléments masqués',
      optHiddenEmpty: 'Les éléments masqués et mémorisés apparaissent ici.', optDark: 'Thème sombre',
      optDarkAll: 'Thème sombre sur tous les sites', optDarkAllDetail: 'Les sites déjà sombres restent tels quels.',
      optDarkSites: 'Sites', optDarkEmpty: 'Activez le thème sombre d’un site depuis l’encoche (⌥⇧D).',
      darkStateOn: 'Sombre', darkStateOff: 'Original',
      optMac: 'SAVISUL pour Mac', optMacConnected: 'Connecté · SAVISUL {0}', optMacOffline: 'L’app n’est pas lancée',
      optMacMissing: 'Non connecté. Ouvrez SAVISUL sur votre Mac une fois.',
      optMacDetail: 'Quand SAVISUL est lancé, l’encoche contrôle le mode capot fermé, la veille et le volume, affiche la batterie et le processeur, et enregistre les captures dans Images › SAVISUL.',
      optShortcuts: 'Raccourcis', optShortcutsChange: 'Modifier les raccourcis', optNotSet: 'Non défini',
      optAbout: 'À propos', optVersion: 'Version {0}', optWelcomeTitle: 'SAVISUL est dans votre navigateur',
      optWelcomeBody: 'Placez le pointeur en haut d’une page ou appuyez sur ⌥⇧N. Rechargez les onglets déjà ouverts.',
      optClearAll: 'Tout supprimer', optConfirmDelete: 'Supprimer toutes les notes ?', optSitePage: 'Page', optSiteWide: 'Site',
      optRules: { one: '{0} règle', other: '{0} règles' }, optTools: 'Dans l’encoche', optOpenNotch: 'ouvre l’encoche sur n’importe quelle page',

      dReader: 'Le texte seul, sans pubs ni encombrement', dColor: 'N’importe quelle couleur à l’écran en HEX, RGB, HSL, avec contraste',
      dRuler: 'Tailles, marges et distances des éléments', dNote: 'Une note liée à la page ou au site entier',
      dDark: 'Thème sombre pour tout site, mémorisé par site', dShot: 'Page entière, zone visible ou sélection',
      dZap: 'Masque bannières et popups, même à la prochaine visite', dFonts: 'Police, taille, graisse et couleur de tout texte',
      dLink: 'Un lien sans traceurs, Markdown et un QR code', dVideo: 'Vitesse jusqu’à 4×, image dans l’image, boucle',
      dImages: 'Toutes les images de la page, avec tailles et téléchargement', dUnlock: 'Copie et clic droit là où le site les bloque',
      dEdit: 'Modifiez n’importe quel texte avant une capture', dOutline: 'Le contour de chaque élément pour voir la mise en page',
      dSpeak: 'Lit à voix haute l’article ou le texte sélectionné', dMac: 'Capot fermé, veille, volume et batterie de votre Mac',

      restricted: 'Le navigateur n’autorise pas les extensions sur cette page',
      reloadNeeded: 'Rechargez la page pour utiliser SAVISUL ici'
    }
  };

  const LOCALES = { en: 'en-US', ru: 'ru-RU', uk: 'uk-UA', fr: 'fr-FR' };
  let current = 'en';

  function detect() {
    let ui = 'en';
    try { ui = (chrome.i18n && chrome.i18n.getUILanguage()) || navigator.language || 'en'; } catch { ui = navigator.language || 'en'; }
    const code = ui.toLowerCase().slice(0, 2);
    return LANGS.includes(code) ? code : 'en';
  }

  // An explicit choice wins; otherwise the extension speaks the language of SAVISUL for Mac,
  // and English until the Mac app has told us its language.
  function resolve(setting, appLanguage) {
    if (LANGS.includes(setting)) return setting;
    if (LANGS.includes(appLanguage)) return appLanguage;
    return 'en';
  }

  function fill(template, args) {
    return template.replace(/\{(\d)\}/g, (_, i) => (args[i] ?? ''));
  }

  function t(key, ...args) {
    const value = S[current][key] ?? S.en[key];
    if (value == null) return key;
    if (typeof value === 'object') return fill(value.other ?? value.one, args);
    return fill(value, args);
  }

  const rules = {};
  function plural(key, count) {
    const value = S[current][key] ?? S.en[key];
    if (typeof value !== 'object') return t(key, number(count));
    rules[current] ||= new Intl.PluralRules(LOCALES[current]);
    const form = rules[current].select(count);
    return fill(value[form] ?? value.other ?? value.one, [number(count)]);
  }

  function number(value, digits = 0, minimum = digits) {
    return new Intl.NumberFormat(LOCALES[current], { minimumFractionDigits: minimum, maximumFractionDigits: digits }).format(value);
  }

  function percent(value) {
    const n = number(Math.round(value));
    return current === 'fr' ? `${n}\u202F%` : `${n}%`;
  }

  // Later files (shared/i18n-browser.js) add their strings here instead of growing this table.
  function extend(strings) {
    for (const [lang, table] of Object.entries(strings)) Object.assign(S[lang] ||= {}, table);
  }

  globalThis.SV_I18N = {
    LANGS, NATIVE, LOCALES, detect, resolve, t, plural, number, percent, extend,
    get lang() { return current; },
    set lang(value) { current = LANGS.includes(value) ? value : 'en'; },
    get locale() { return LOCALES[current]; }
  };
})();
