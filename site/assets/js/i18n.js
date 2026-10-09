// English is the default; Russian is the one switch. Strings use {0}, {1} placeholders.
const STRINGS = {
  en: {
    metaTitle: 'SAVISUL — a native Mac app, not a notch widget',
    metaDescription: 'SAVISUL is a free, open-source Mac utility: one native app for the command bar, clipboard and shelf, windows, per-app volume, automations, AI actions and a browser extension. The island around the camera is one part of the app.',

    // Menu bar
    menuGuide: 'Field guide',
    menuChrome: 'Chrome',
    menuPrivacy: 'Privacy',
    menuOpen: 'Open source',
    menuDownload: 'Download',
    menuAbout: 'About SAVISUL',
    menuDownloadMac: 'Download for Mac…',
    menuZip: 'Download ZIP archive',
    menuGithub: 'View on GitHub',
    menuPolicy: 'Privacy Policy',
    menuLicense: 'License',
    menuContact: 'Contact',
    menuLanguage: 'Language',
    menuPanel: 'SAVISUL panel',
    menuSearch: 'Command bar',

    // Hero
    heroTitle: 'A full Mac app. Not a notch widget.',
    heroLead: 'SAVISUL is one native utility: command bar, clipboard and shelf, windows, per-app volume, automations, AI actions and a browser extension. The island around the camera is one part of that app.',
    heroDownload: 'Download for Mac',
    heroGuide: 'Read the field guide',
    heroMeta: 'Version {0} · macOS {1} or later · {2} · Free and open source',
    heroLive: 'This desktop is live — hover the island.',
    heroLiveTouch: 'This desktop is live — tap the island.',

    // Start here note
    noteTitle: 'Start here',
    noteItems: [
      ['island', 'Hover the island at the top'],
      ['search', '⌥Space opens the command bar. Try “10 km in miles”'],
      ['clipboard', '⌃⌥V shows clipboard history'],
      ['switch', 'Hold ⌥ and press Tab to switch windows'],
      ['snap', 'Drag this note to the left edge'],
      ['browser', 'Open the browser in the Dock']
    ],
    noteItemsTouch: [
      ['island', 'Tap the island at the top'],
      ['search', 'Open the command bar'],
      ['clipboard', 'Open clipboard history'],
      ['browser', 'Open the browser with the notch'],
      ['panel', 'Open the SAVISUL panel']
    ],
    noteFoot: 'Everything here runs in your browser with sample data.',

    // Windows and Dock
    winPanel: 'SAVISUL',
    winBrowser: 'Browser',
    winNote: 'Start here',
    winTerminal: 'Terminal',
    dockDownload: 'Download',
    dockSavisul: 'SAVISUL',
    switcherHint: 'Q quit · W close · M minimize · H hide',
    snapHint: 'Release to snap',

    // Terminal
    termLines: [
      ['dim', 'Last login on ttys001'],
      ['cmd', 'open ~/Downloads/SAVISUL-{0}.dmg'],
      ['note', '# Drag SAVISUL into Applications, then open it.'],
      ['note', '# If macOS says it can’t check the app:'],
      ['note', '#   System Settings → Privacy & Security → Open Anyway'],
      ['note', '# Or run the script from “If it won’t open.txt”.']
    ],
    termDownload: 'Download SAVISUL-{0}.dmg',
    termHelp: 'Get “If it won’t open.txt”',

    // Island
    tabHome: 'Home',
    tabAgents: 'Agents',
    tabFiles: 'Files',
    tabCamera: 'Camera',
    islandPin: 'Keep open',
    islandSettings: 'Island settings',
    play: 'Play',
    pause: 'Pause',
    prevTrack: 'Previous track',
    nextTrack: 'Next track',
    eventTitle: 'Design review',
    eventWhen: 'in {0} min · Zoom',
    timerLabel: 'Timer',
    timerMin: '{0} min',
    timerAdd: 'Add a minute',
    timerStop: 'Stop timer',
    agentsSummary: '1 working · 2 idle',
    agentWorking: 'Working · {0} min',
    agentIdle: 'Idle · {0} min ago',
    agentFinished: 'Finished · {0} min ago',
    agentNone: 'No sessions yet',
    agentUsage: '{0} tokens today · limit resets {1}',
    shelf: 'Shelf',
    shelfDrop: 'Drop files here to keep them handy',
    shelfShake: 'Or shake the pointer while dragging',
    shelfLocal: 'Files never leave your browser',
    shelfClear: 'Clear shelf',
    downloads: 'Downloads',
    dlNow: 'now',
    dlMin: '{0} min ago',
    dlHour: '{0} h ago',
    dlYesterday: 'yesterday',
    cameraTitle: 'Check yourself before a call',
    cameraOn: 'Turn on camera',
    cameraOff: 'Turn off',
    cameraNote: 'Nothing is recorded or saved.',
    cameraError: 'The camera isn’t available here.',
    peekAgent: ['Claude Code finished', 'savisul-site · 12 min'],
    peekCharging: ['Charging', '82% · full in 48 min'],
    peekHeadphones: ['Headphones removed', 'Volume lowered to 30%'],
    peekMeeting: ['Design review in 5 min', 'Zoom'],
    peekDownload: ['Download finished', 'SAVISUL-{0}.dmg'],
    peekTimer: ['Timer finished', '{0} min'],
    peekCopied: ['Copied', '{0}'],
    peekMics: ['All microphones muted', '⌃⌥M turns them back on'],
    peekMicsOn: ['Microphones on', 'Everyone can hear you again'],
    peekOutput: ['Output', '{0}'],
    peekOpening: ['Opening', '{0}'],
    peekPasted: ['Pasted', '{0}'],
    peekPlain: ['Pasted as plain text', '{0}'],

    // Panel
    pEnergy: 'Energy',
    pSound: 'Sound',
    pSystem: 'System',
    pWork: 'Work',
    pTools: 'Tools',
    pSettings: 'Settings',
    pAwake: 'Awake',
    pMore: 'More',
    energyOnSub: 'The Mac keeps working with the lid closed',
    energyOffSub: 'The Mac sleeps when you close the lid',
    lidMode: 'Closed-lid mode',
    lidOnFor: 'On for {0}',
    lidOff: 'Off',
    lidNote: 'System sleep stays off until you turn this off here, even if you quit SAVISUL.',
    lidPassword: 'In the app, macOS asks for an administrator password first.',
    charging: 'Charging',
    chargingValue: '82% · full in 48 min',
    idleSleep: 'Idle sleep',
    never: 'Never',
    keptAwake: 'Kept awake by',
    preventIdle: 'Prevent idle sleep',
    preventIdleNote: 'Stays awake while the lid is open. No password needed.',
    displayOff: 'Display off',
    soundSub: 'Each app has its own volume',
    output: 'Output',
    devices: ['MacBook Speakers', 'Headphones', 'Studio Display'],
    mixApps: [['music', 'Music'], ['video', 'Zoom'], ['globe', 'Browser']],
    boost: 'Above 100% boosts a quiet app',
    nextOutput: 'Next output',
    muteMics: 'Mute all mics',
    micsMuted: 'Mics muted',
    systemSub: 'Processor {0}% · Memory {1}%',
    processor: 'Processor',
    memory: 'Memory',
    memoryOf: '{0} GB of 24 GB',
    pressureHigh: 'High pressure',
    pressureOk: 'Normal pressure',
    swap: 'Swap {0} GB',
    battery: 'Battery',
    batteryFull: 'full in 48 min',
    batteryHealth: 'Health 94% · 176 cycles',
    temperature: 'Temperature',
    chipSensor: 'Chip sensor',
    fans: 'Fans: {0} rpm',
    busiest: 'Busiest apps',
    workSubToday: '{0} in editors today',
    workSubWeek: '{0} in editors this week',
    today: 'Today',
    week: '7 days',
    inEditors: 'In editors',
    typed: 'Typed',
    tokens: '≈ Tokens',
    aiApps: 'AI apps',
    editors: 'Editors',
    assistants: 'AI assistants',
    charsTokens: '{0} chars · ≈{1} tokens',
    workPrivacy: 'Counts only. SAVISUL never stores what you type.',
    toolsSub: 'Capture, record and your own commands',
    toolList: [
      ['crop', 'Capture area', 'Drag to choose an area'],
      ['window', 'Capture window', 'Click a window to capture it'],
      ['screen', 'Capture screen', 'Saved to Pictures › SAVISUL'],
      ['video', 'Record screen', 'Recording starts after a 3-second count'],
      ['bolt', 'Alerts', 'Tell me when CPU, memory, battery or heat cross a line'],
      ['cpu', 'Activity Monitor', 'Opening Activity Monitor'],
      ['terminal', 'Terminal', 'Opening Terminal'],
      ['globe', 'Copy IP address', 'Copied 192.168.1.24'],
      ['eyeOff', 'Hidden files', 'Finder now shows hidden files'],
      ['displayOff', 'Display off', 'In the app, the screen goes dark now']
    ],
    settingsSub: 'Language, island and shortcuts',
    setLanguage: 'Language',
    setLanguageNote: 'The Chrome extension follows this language.',
    setLaunch: 'Open at login',
    setHover: 'Open the island on hover',
    setShortcuts: 'Panel ⌃⌥S · Command bar ⌥Space · Clipboard ⌃⌥V',

    // Browser + extension
    pageTitle: 'Les trains de nuit',
    pageHost: 'fieldnotes.example',
    pagePath: '/trains-de-nuit?utm_source=newsletter&utm_medium=email&fbclid=AbX9',
    pageNotchHint: 'Hover the top of the page',
    tTools: 'Tools',
    tThisPage: 'This page',
    tBrowser: 'Browser',
    extToolNames: {
      color: 'Color', ruler: 'Ruler', note: 'Note', shot: 'Screenshot', hide: 'Hide', fonts: 'Fonts', css: 'CSS',
      link: 'Link · QR', data: 'Data', translate: 'Translate', save: 'Save page', video: 'Video', media: 'Media',
      images: 'Images', speak: 'Read aloud', reader: 'Reader', dark: 'Dark', copy: 'Free copy', edit: 'Edit',
      outlines: 'Outlines', tabs: 'Tabs', sessions: 'Sessions', ai: 'AI', shelf: 'To Shelf', bookmarks: 'Bookmarks', notes: 'Notes'
    },
    extDarkOn: 'Dark theme on for fieldnotes.example',
    extDarkOff: 'Dark theme off',
    extReaderOn: 'Reader on · Esc closes it',
    extHideHint: 'Click anything on the page to hide it',
    extHidden: 'Hidden · {0} element(s)',
    extRestore: 'Restore',
    extRulerHint: 'Hover to measure an element',
    extColorHint: 'Hover to read a color · click to copy',
    extFontsHint: 'Hover text to read its font',
    extCopied: 'Copied {0}',
    extTranslated: 'Translated from French',
    extOriginal: 'Original restored',
    extEditOn: 'Click any text to edit it',
    extEditOff: 'Editing off',
    extOutlinesOn: 'Outlines on',
    extOutlinesOff: 'Outlines off',
    extInExtension: '{0} works on real pages in the extension',
    extNoteTitle: 'Note for this page',
    extNotePlaceholder: 'Write something to find here next time…',
    extNoteSaved: 'Saved for this page',
    extLinkTitle: 'Clean link',
    extTrackers: '{0} trackers removed',
    extCopyLink: 'Copy link',
    extCopyMd: 'Copy Markdown',
    extStop: 'Done',
    extEsc: 'Esc',

    // Command bar
    cmdPlaceholder: 'Apps, windows, clipboard, math — try “10 km in miles”',
    cmdCalc: 'Calculator',
    cmdConvert: 'Convert',
    cmdApps: 'Applications',
    cmdWindows: 'Windows',
    cmdClipboard: 'Clipboard',
    cmdMenu: 'Panel',
    cmdLayout: 'Wrong keyboard layout · showing “{0}”',
    cmdWeb: 'Search the web for “{0}”',
    cmdHint: '↩ Open · esc Close',
    cmdOpening: 'Opening {0}',
    cmdRates: 'Sample rates · the app downloads daily rates',
    cmdEmpty: 'Nothing found',
    apps: ['Safari', 'Terminal', 'Cursor', 'Xcode', 'Music', 'Calendar', 'Notes', 'Mail', 'Finder', 'System Settings', 'Visual Studio Code', 'Activity Monitor'],

    // Clipboard
    clipTitle: 'Clipboard',
    clipSearch: 'Search history',
    clipHint: '↩ Paste · ⇧↩ Paste as plain text',
    clipPasted: 'Pasted',
    clipPlain: 'Pasted as plain text',
    clipEmpty: 'Nothing matches',
    clipFromPage: 'Copied on this page',
    clipKinds: { text: 'Text', link: 'Link', color: 'Color', file: 'File', image: 'Image' },

    // Field guide
    guideTitle: 'Everything it does, in plain words.',
    guideLead: 'SAVISUL is one native Mac app that replaces a pile of small utilities. No account and no subscription.',
    showMe: 'Show me',
    plateRest: 'At rest',
    plateEvent: 'An event',
    plateHover: 'On hover',
    snapNames: { left: 'Left half', left23: 'Left two thirds', left13: 'Left third', right: 'Right half', right23: 'Right two thirds', right13: 'Right third', max: 'Almost full screen', restore: 'Where it was' },
    plateTry: 'Try: 2+2, 10 km in miles, 100 $ in eur, ыфафкш',

    islandTitle: 'The notch, awake.',
    islandBody: 'At rest the island is a thin strip around the camera. Hover it and it opens into four tabs. Events open it on their own and close it again: a finished agent, a charger, headphones, a muted microphone, a download.',
    islandRows: [
      ['music', 'Music', 'Cover, controls and lyrics synced to the line. The equalizer follows that app’s sound.'],
      ['calendar', 'Calendar and timers', 'Your next meeting ahead of time, a reminder five minutes before. Timers for 1, 5, 10 or 25 minutes.'],
      ['sparkle', 'AI agents', 'Claude Code, Codex, Cursor, OpenCode and Copilot: who is working, on which project and model, tokens and the code they wrote today, when the limit resets. Start a new task for any of them from here.'],
      ['tray', 'Files and camera', 'A shelf for files you’re not done with, recent downloads, and a camera mirror before calls. Nothing is recorded.'],
      ['loop', 'Live activities', 'Long jobs — an automation, reading text, converting, asking AI — wait around the camera with a ring and a percentage.']
    ],
    islandAction: 'Open the island',

    soundTitle: 'Every app gets its own volume.',
    soundBody: 'Your Mac has one volume for everything. SAVISUL adds a second: each app gets its own level, output and ceiling. Lift a quiet video to 160% and keep music on the speakers while the call goes to your headset.',
    soundKeys: [
      ['⌃⌥O', 'Switch the whole Mac to the next output'],
      ['⌃⌥M', 'Mute every microphone and keep it muted'],
      ['icon:headphones', 'Headphones gone? The volume drops before the room hears it']
    ],
    soundAction: 'Open Sound in the panel',

    windowsTitle: 'Windows land where you meant.',
    windowsBody: '⌥Tab shows apps with live window previews. Drag a window to an edge and it takes a half or a corner. An accidental ⌘Q no longer quits: hold it or press it twice.',
    windowsKeys: [
      ['⌥Tab', 'Switcher with live previews; Q, W, M and H act on the window'],
      ['⌃⌥← ⌃⌥→', 'Left or right half; press again for two thirds, then one third'],
      ['⌃⌥↩', 'Almost full screen'],
      ['⌃⌥⌫', 'Back to where it was'],
      ['⌃⌘ + drag', 'Move with the left button, resize with the right']
    ],
    windowsAction: 'Snap the note to the left',

    clipTitleGuide: 'It remembers. It searches. It counts.',
    clipBody: 'History keeps up to a thousand items: text, links, images, files and colors. Next to it, one field searches apps, windows, files, the clipboard and the menus of the app in front, and does the math.',
    clipKeys: [
      ['⌃⌥V', 'Clipboard history; ↩ pastes, ⇧↩ pastes plain text'],
      ['⌥Space', 'Command bar: “2+2”, “10 km in miles”, “100 $ in eur”'],
      ['icon:keyboard', 'Wrong layout? “ыфафкш” still finds Safari'],
      ['⌃⌥R', 'Hold for a ring of eight favorite actions'],
      ['icon:tray', 'Shake a file while dragging and a shelf appears']
    ],
    clipAction: 'Open the command bar',

    actionsTitle: 'Select anything. Press ⌃⌥A.',
    actionsBody: 'Text, a link, an image or files in any app: SAVISUL reads what you selected and offers only what fits it. Nothing selected? It works on the clipboard. The same actions run from the command bar, the Shelf and automations.',
    actionsKeys: [
      ['⌃⌥A', 'Actions for the selection in any app; ↩ runs, ⌘1–9 picks'],
      ['icon:image', 'Images: read the text right on the Mac, pin above every window, convert to PNG, JPEG or HEIC, compress'],
      ['icon:link', 'Links: strip trackers, make a QR code, summarize the page'],
      ['icon:folder', 'Files: ZIP, rename a batch, move, share, copy the path'],
      ['icon:sparkle', 'AI: summarize, translate, rewrite, explain or ask — on your own API key']
    ],
    actionsAI: 'AI',
    ctxKinds: [
      { label: 'Text', icon: 'type', head: 'Text · 47 characters', sample: 'SAVISUL turns the notch into a living island.', actions: [
        ['sparkle', 'Summarize', true, 'Runs on your own API key (Anthropic, OpenAI, Gemini, Ollama and more). Without a key nothing is sent.'],
        ['translate', 'Translate', true, 'Into the app’s language; text already in it goes to English. Your key, your provider.'],
        ['pencil', 'Rewrite', true, 'Clearer wording in the same tone and language, ready to paste back with ⌘↩.'],
        ['hash', 'Count words', false, 'Words: 8 · Characters: 47 · Lines: 1'],
        ['qr', 'QR code', false, 'The QR code is pinned above every window. Scroll to resize, double-click to close.'],
        ['tray', 'Add to Shelf', false, 'On the shelf.']
      ] },
      { label: 'Link', icon: 'link', head: 'Link · shop.example', sample: 'https://shop.example/item?id=7&utm_source=mail&fbclid=Xz', actions: [
        ['globe', 'Open in browser', false, 'Opened in your default browser.'],
        ['sparkle', 'Clean link', false, 'https://shop.example/item?id=7 · 2 trackers removed · copied'],
        ['page', 'Summarize page', true, 'Reads the page and sums it up on your own API key.'],
        ['qr', 'QR code', false, 'The QR code is pinned above every window.']
      ] },
      { label: 'Image', icon: 'image', head: 'Image · 1440×900', sample: 'receipt.png', actions: [
        ['type', 'Recognize text', false, 'CAFÉ NORD · Flat white 4.50 · Croissant 3.20 · Total 7.70 — read on the Mac, nothing uploaded.'],
        ['pin', 'Pin to screen', false, 'Pinned above every window. Drag it anywhere.'],
        ['refresh', 'Convert to JPEG', false, 'receipt.jpg · 312 KB, next to the original'],
        ['archive', 'Compress image', false, '1.8 MB → 412 KB · receipt (compressed).jpg']
      ] },
      { label: 'Files', icon: 'folder', head: '3 items', sample: 'IMG_0412.heic, IMG_0413.heic, IMG_0414.heic', actions: [
        ['archive', 'Compress to ZIP', false, 'Archive.zip · 9.6 MB, next to the photos'],
        ['pencil', 'Rename…', false, 'Trip 1.heic, Trip 2.heic, Trip 3.heic'],
        ['folder', 'Move to…', false, 'Pick a folder and they move there.'],
        ['send', 'Share…', false, 'AirDrop, Messages, Mail and the rest of the share sheet.']
      ] }
    ],
    ctxPick: 'Pick an action',

    autoTitle: 'When this happens, do that.',
    autoBody: 'Automations watch for something on your Mac and do the steps for you, even with the panel closed. Each run shows its progress around the notch, and a step that fails says why.',
    autoRows: [
      ['headphones', 'When', 'Headphones connect or disconnect, a file lands in a folder, an app opens or quits, an AI agent finishes, the battery drops, the charger connects, or at a set time.'],
      ['sliders', 'If', 'Battery level, on the charger or not, an app is open, a time window, days of the week, the current sound output.'],
      ['play', 'Do', 'Volume and output, microphones, open or quit apps, a Shortcut, any SAVISUL feature or action, rename and move the file, the Shelf, a notice in the island.'],
      ['sparkle', 'Live activities', 'Anything that takes a moment — an automation, reading text, converting files, asking AI — shows a ring and a percentage around the notch.']
    ],
    autoAction: 'Open Automations in the panel',
    autoWhen: 'When',
    autoIf: 'If',
    autoDo: 'Do',
    autoRun: 'Run it',
    autoRunning: 'Running…',
    autoDone: 'Done',
    autoTemplates: [
      { label: 'AirPods', icon: 'headphones', when: 'AirPods connect', cond: '', steps: ['Switch the output to AirPods', 'Set the volume to 35%', 'Show “AirPods · 35%” in the island'], done: 'AirPods · 35%' },
      { label: 'PDF', icon: 'page', when: 'A PDF lands in Downloads', cond: '', steps: ['Rename it “2026-10-07 invoice.pdf”', 'Move it to Documents/PDF', 'Put it on the Shelf'], done: '2026-10-07 invoice.pdf' },
      { label: 'Agent', icon: 'sparkle', when: 'An AI agent finishes', cond: 'It worked longer than a minute', steps: ['Show “Codex · SAVISUL”', 'Play the “Glass” sound', 'Open Cursor'], done: 'Codex · SAVISUL' },
      { label: 'Battery', icon: 'battery', when: 'The battery drops below 20%', cond: 'On battery power', steps: ['Turn off the equalizer', 'Turn off synced lyrics', 'Warn in the island'], done: 'Battery 19% · heavy features off' }
    ],

    chromeTitle: 'The same notch on every web page.',
    chromeBody: 'The extension puts a notch at the top of any site. Hover the top edge or press ⌥⇧N: reader, dark theme, color picker, ruler, CSS inspector, translation, page notes, full-page screenshots, clean links with a QR code and data export, plus a side panel for tabs, sessions, bookmarks and AI.',
    chromeRows: [
      ['download', 'Ships inside the app', 'SAVISUL opens your browser’s extensions page and the extension folder. Turn on Developer mode, click Load unpacked, pick the folder. Once.'],
      ['globe', 'Any Chromium browser', 'Chrome, Edge, Brave, Opera, Vivaldi and Yandex Browser.'],
      ['laptop', 'Talks to your Mac', 'While the app runs, the page notch shows the lid, sleep, volume and battery, and the extension follows the app’s language.']
    ],
    chromeAction: 'Open the browser',

    panelTitle: 'Your Mac, in one panel.',
    panelBody: '⌃⌥S opens a panel for the machine itself, in English, Russian, Ukrainian or French.',
    panelRows: [
      ['bolt', 'Energy', 'Closed-lid mode keeps the Mac awake with the lid shut. Battery, adapter and what is keeping it awake.'],
      ['cpu', 'System', 'Processor, memory pressure, temperature and which apps weigh the most. Fan control: automatic, smart, max or manual, always within the fans’ own limits and at full speed past 95 °C.'],
      ['code', 'Work', 'Time in editors and AI apps today and this week, how much you typed, and what the AI did in VS Code and Cursor: model, tokens, lines added and files created. Counts only, never the text.'],
      ['grid', 'Tools', 'Automations, captures of an area, a window or the screen, screen recording, alerts when a sensor crosses your line, your own commands.']
    ],
    panelAction: 'Open the panel',

    privacyTitle: 'Stays on your Mac.',
    privacyLead: 'No account, no analytics, no ads, no telemetry. Settings, clipboard history, notes and stats live in your user folder. These are the only times SAVISUL talks to the internet.',
    privacyHead: ['When', 'What leaves your Mac', 'Where'],
    privacyRows: [
      ['A song starts playing', 'Title, artist, album and length, to find synced lyrics', 'lrclib.net'],
      ['You convert currency in the command bar', 'Nothing about you: it downloads daily exchange rates', 'open.er-api.com'],
      ['You choose “Search the web”', 'Your query, in your own browser', 'Google'],
      ['You use AI in the extension with your own key', 'The page text and your question', 'Anthropic'],
      ['You run an AI action with your own key', 'The selected text, page or image and your question', 'The service you chose'],
      ['Chrome can’t translate on the device', 'The page address, in a new tab', 'Google Translate']
    ],
    privacyLink: 'Read the privacy policy',

    installTitle: 'Install in a minute.',
    installSteps: [
      ['Download the disk image', 'Double-click it and drag SAVISUL into Applications. The ZIP holds the same app.'],
      ['Open it', 'The build is signed on our own machine, not notarized by Apple, so macOS may stop the first launch. Open System Settings → Privacy & Security and click Open Anyway, or run the script from “If it won’t open.txt”.'],
      ['Allow only what you use', 'Each permission is asked when its feature needs it.'],
      ['Add the browser notch', 'SAVISUL opens your browser’s extensions page and the folder for you. Developer mode → Load unpacked → pick the folder.']
    ],
    permissions: [
      ['Screen Recording', 'live window previews'],
      ['Audio capture', 'per-app volume'],
      ['Accessibility', 'windows, menus and the Dock'],
      ['Calendar, Camera, Downloads', 'only when you turn them on']
    ],
    installHelp: 'If it won’t open.txt',

    openTitle: 'Open source, with credit where it’s due.',
    openLead: 'SAVISUL is published under the Apache License 2.0. Use it, change it, ship it, commercially too. If you distribute SAVISUL or anything built on it, keep the NOTICE file and credit the original.',
    openMayTitle: 'You may',
    openMay: ['Use it at home and at work, including commercially', 'Change it and publish your changes', 'Distribute and sell your own builds'],
    openMustTitle: 'You must',
    openMust: ['Include the license and the NOTICE file', 'Credit SAVISUL in your About window or documentation', 'Mark the files you changed', 'Use your own name and logo: “SAVISUL” is not licensed'],
    creditLabel: 'Credit line',
    creditLine: 'Based on SAVISUL by The SAVISUL Authors · Apache License 2.0',
    copyCredit: 'Copy',
    copied: 'Copied',
    readLicense: 'Read the license',
    viewGithub: 'View on GitHub',

    finalTitle: 'Put your notch to work.',
    finalZip: 'ZIP archive',
    finalQuestions: 'Questions or ideas? {0}',

    footerRights: '© {0} The SAVISUL Authors',
    footerPrivacy: 'Privacy',
    footerLicense: 'License',
    footerContact: 'Contact',
    footerTrademarks: 'Not affiliated with Apple Inc. or Google LLC. Mac, MacBook and macOS are trademarks of Apple Inc. Chrome is a trademark of Google LLC.',
    langName: 'English',

    // Documents
    docUpdated: 'Last updated {0}',
    docBack: 'Back to SAVISUL',
    docContents: 'On this page',
    notFoundTitle: 'This window doesn’t exist.',
    notFoundBody: 'The page you opened isn’t here. It may have moved or never existed.',
    notFoundHome: 'Go to SAVISUL'
  },

  ru: {
    metaTitle: 'SAVISUL — полноценное приложение для Mac',
    metaDescription: 'SAVISUL — бесплатная утилита для macOS с открытым кодом. Это одно нативное приложение: командная строка, буфер и полка, окна, звук по приложениям, автоматизации, действия ИИ и расширение для браузера. Островок у камеры — часть приложения, а не вся программа.',

    menuGuide: 'Путеводитель',
    menuChrome: 'Chrome',
    menuPrivacy: 'Приватность',
    menuOpen: 'Открытый код',
    menuDownload: 'Скачать',
    menuAbout: 'О SAVISUL',
    menuDownloadMac: 'Скачать для Mac…',
    menuZip: 'Скачать архив ZIP',
    menuGithub: 'Открыть на GitHub',
    menuPolicy: 'Политика конфиденциальности',
    menuLicense: 'Лицензия',
    menuContact: 'Написать нам',
    menuLanguage: 'Язык',
    menuPanel: 'Панель SAVISUL',
    menuSearch: 'Командная строка',

    heroTitle: 'Полноценное приложение для Mac.',
    heroLead: 'SAVISUL — одна нативная утилита: командная строка, буфер и полка, окна, своя громкость у каждого приложения, автоматизации, действия ИИ и расширение для браузера. Островок у камеры входит в это приложение, а не заменяет его.',
    heroDownload: 'Скачать для Mac',
    heroGuide: 'Читать путеводитель',
    heroMeta: 'Версия {0} · macOS {1} и новее · {2} · Бесплатно, открытый код',
    heroLive: 'Этот рабочий стол живой — наведите на островок.',
    heroLiveTouch: 'Этот рабочий стол живой — нажмите на островок.',

    noteTitle: 'С чего начать',
    noteItems: [
      ['island', 'Наведите на островок наверху'],
      ['search', '⌥Space — командная строка. Попробуйте «10 км в мили»'],
      ['clipboard', '⌃⌥V — история буфера'],
      ['switch', 'Держите ⌥ и жмите Tab, чтобы переключать окна'],
      ['snap', 'Перетащите эту заметку к левому краю'],
      ['browser', 'Откройте браузер в Dock']
    ],
    noteItemsTouch: [
      ['island', 'Нажмите на островок наверху'],
      ['search', 'Открыть командную строку'],
      ['clipboard', 'Открыть историю буфера'],
      ['browser', 'Открыть браузер с чёлкой'],
      ['panel', 'Открыть панель SAVISUL']
    ],
    noteFoot: 'Всё здесь работает прямо в браузере, на примерах.',

    winPanel: 'SAVISUL',
    winBrowser: 'Браузер',
    winNote: 'С чего начать',
    winTerminal: 'Терминал',
    dockDownload: 'Скачать',
    dockSavisul: 'SAVISUL',
    switcherHint: 'Q — завершить · W — закрыть · M — свернуть · H — скрыть',
    snapHint: 'Отпустите, чтобы окно встало',

    termLines: [
      ['dim', 'Last login on ttys001'],
      ['cmd', 'open ~/Downloads/SAVISUL-{0}.dmg'],
      ['note', '# Перетащите SAVISUL в «Программы» и откройте.'],
      ['note', '# Если macOS не может проверить приложение:'],
      ['note', '#   Системные настройки → Конфиденциальность и безопасность → Всё равно открыть'],
      ['note', '# Или запустите скрипт из «Если не открывается.txt».']
    ],
    termDownload: 'Скачать SAVISUL-{0}.dmg',
    termHelp: 'Скачать «Если не открывается.txt»',

    tabHome: 'Главное',
    tabAgents: 'Агенты',
    tabFiles: 'Файлы',
    tabCamera: 'Камера',
    islandPin: 'Не закрывать',
    islandSettings: 'Настройки островка',
    play: 'Играть',
    pause: 'Пауза',
    prevTrack: 'Предыдущий трек',
    nextTrack: 'Следующий трек',
    eventTitle: 'Разбор дизайна',
    eventWhen: 'через {0} мин · Zoom',
    timerLabel: 'Таймер',
    timerMin: '{0} мин',
    timerAdd: 'Добавить минуту',
    timerStop: 'Остановить таймер',
    agentsSummary: '1 работает · 2 ждут',
    agentWorking: 'Работает · {0} мин',
    agentIdle: 'Ждёт · {0} мин назад',
    agentFinished: 'Закончил · {0} мин назад',
    agentNone: 'Сессий пока нет',
    agentUsage: '{0} токенов сегодня · лимит сбросится в {1}',
    shelf: 'Полка',
    shelfDrop: 'Бросьте сюда файлы, чтобы держать под рукой',
    shelfShake: 'Или встряхните курсор при перетаскивании',
    shelfLocal: 'Файлы не покидают ваш браузер',
    shelfClear: 'Очистить полку',
    downloads: 'Загрузки',
    dlNow: 'только что',
    dlMin: '{0} мин назад',
    dlHour: '{0} ч назад',
    dlYesterday: 'вчера',
    cameraTitle: 'Посмотрите на себя перед звонком',
    cameraOn: 'Включить камеру',
    cameraOff: 'Выключить',
    cameraNote: 'Ничего не записывается и не сохраняется.',
    cameraError: 'Камера здесь недоступна.',
    peekAgent: ['Claude Code закончил', 'savisul-site · 12 мин'],
    peekCharging: ['Зарядка', '82% · полная через 48 мин'],
    peekHeadphones: ['Наушники сняты', 'Громкость снижена до 30%'],
    peekMeeting: ['Разбор дизайна через 5 мин', 'Zoom'],
    peekDownload: ['Загрузка завершена', 'SAVISUL-{0}.dmg'],
    peekTimer: ['Таймер закончился', '{0} мин'],
    peekCopied: ['Скопировано', '{0}'],
    peekMics: ['Все микрофоны выключены', '⌃⌥M включит их обратно'],
    peekMicsOn: ['Микрофоны включены', 'Вас снова слышно'],
    peekOutput: ['Вывод звука', '{0}'],
    peekOpening: ['Открываю', '{0}'],
    peekPasted: ['Вставлено', '{0}'],
    peekPlain: ['Вставлено без форматирования', '{0}'],

    pEnergy: 'Питание',
    pSound: 'Звук',
    pSystem: 'Система',
    pWork: 'Работа',
    pTools: 'Инструменты',
    pSettings: 'Настройки',
    pAwake: 'Не спать',
    pMore: 'Ещё',
    energyOnSub: 'Mac работает с закрытой крышкой',
    energyOffSub: 'Mac засыпает, когда закрываете крышку',
    lidMode: 'Режим закрытой крышки',
    lidOnFor: 'Включён {0}',
    lidOff: 'Выключен',
    lidNote: 'Сон системы выключен, пока вы не выключите режим здесь, даже если закрыть SAVISUL.',
    lidPassword: 'В приложении macOS сначала спросит пароль администратора.',
    charging: 'Зарядка',
    chargingValue: '82% · полная через 48 мин',
    idleSleep: 'Сон в простое',
    never: 'Никогда',
    keptAwake: 'Не даёт уснуть',
    preventIdle: 'Не засыпать в простое',
    preventIdleNote: 'Mac не спит, пока крышка открыта. Пароль не нужен.',
    displayOff: 'Погасить экран',
    soundSub: 'У каждого приложения своя громкость',
    output: 'Вывод',
    devices: ['Динамики MacBook', 'Наушники', 'Studio Display'],
    mixApps: [['music', 'Музыка'], ['video', 'Zoom'], ['globe', 'Браузер']],
    boost: 'Выше 100% — усиление для тихих приложений',
    nextOutput: 'Следующий выход',
    muteMics: 'Выключить микрофоны',
    micsMuted: 'Микрофоны выключены',
    systemSub: 'ЦП {0}% · Память {1}%',
    processor: 'Процессор',
    memory: 'Память',
    memoryOf: '{0} ГБ из 24 ГБ',
    pressureHigh: 'Высокое давление',
    pressureOk: 'Давление в норме',
    swap: 'Подкачка {0} ГБ',
    battery: 'Батарея',
    batteryFull: 'полная через 48 мин',
    batteryHealth: 'Здоровье 94% · 176 циклов',
    temperature: 'Температура',
    chipSensor: 'Датчик чипа',
    fans: 'Вентиляторы: {0} об/мин',
    busiest: 'Тяжелее всех',
    workSubToday: '{0} в редакторах сегодня',
    workSubWeek: '{0} в редакторах за неделю',
    today: 'Сегодня',
    week: '7 дней',
    inEditors: 'В редакторах',
    typed: 'Напечатано',
    tokens: '≈ Токенов',
    aiApps: 'ИИ-приложения',
    editors: 'Редакторы',
    assistants: 'ИИ-ассистенты',
    charsTokens: '{0} знаков · ≈{1} токенов',
    workPrivacy: 'Только счётчики. SAVISUL никогда не хранит то, что вы печатаете.',
    toolsSub: 'Снимки, запись и ваши команды',
    toolList: [
      ['crop', 'Снимок области', 'Выделите область мышью'],
      ['window', 'Снимок окна', 'Щёлкните по окну, чтобы снять его'],
      ['screen', 'Снимок экрана', 'Сохранено в «Изображения › SAVISUL»'],
      ['video', 'Запись экрана', 'Запись начнётся после отсчёта 3 секунды'],
      ['bolt', 'Оповещения', 'Сообщим, когда процессор, память, батарея или температура перейдут порог'],
      ['cpu', 'Мониторинг системы', 'Открываю «Мониторинг системы»'],
      ['terminal', 'Терминал', 'Открываю Терминал'],
      ['globe', 'Скопировать IP', 'Скопировано 192.168.1.24'],
      ['eyeOff', 'Скрытые файлы', 'Finder теперь показывает скрытые файлы'],
      ['displayOff', 'Погасить экран', 'В приложении экран сейчас погаснет']
    ],
    settingsSub: 'Язык, островок и сочетания клавиш',
    setLanguage: 'Язык',
    setLanguageNote: 'Расширение для Chrome подхватит этот язык.',
    setLaunch: 'Открывать при входе',
    setHover: 'Открывать островок наведением',
    setShortcuts: 'Панель ⌃⌥S · Командная строка ⌥Space · Буфер ⌃⌥V',

    pageTitle: 'Les trains de nuit',
    pageHost: 'fieldnotes.example',
    pagePath: '/trains-de-nuit?utm_source=newsletter&utm_medium=email&fbclid=AbX9',
    pageNotchHint: 'Наведите на верх страницы',
    tTools: 'Инструменты',
    tThisPage: 'Эта страница',
    tBrowser: 'Браузер',
    extToolNames: {
      color: 'Пипетка', ruler: 'Линейка', note: 'Заметка', shot: 'Снимок', hide: 'Спрятать', fonts: 'Шрифт', css: 'CSS',
      link: 'Ссылка · QR', data: 'Данные', translate: 'Перевод', save: 'Сохранить', video: 'Видео', media: 'Медиа',
      images: 'Картинки', speak: 'Озвучить', reader: 'Чтение', dark: 'Тёмная', copy: 'Копирование', edit: 'Правка',
      outlines: 'Контуры', tabs: 'Вкладки', sessions: 'Сессии', ai: 'ИИ', shelf: 'На полку', bookmarks: 'Закладки', notes: 'Заметки'
    },
    extDarkOn: 'Тёмная тема для fieldnotes.example',
    extDarkOff: 'Тёмная тема выключена',
    extReaderOn: 'Режим чтения · Esc закрывает',
    extHideHint: 'Щёлкните по любому блоку, чтобы спрятать',
    extHidden: 'Спрятано блоков: {0}',
    extRestore: 'Вернуть',
    extRulerHint: 'Наведите, чтобы измерить блок',
    extColorHint: 'Наведите, чтобы узнать цвет · щелчок копирует',
    extFontsHint: 'Наведите на текст, чтобы узнать шрифт',
    extCopied: 'Скопировано {0}',
    extTranslated: 'Переведено с французского',
    extOriginal: 'Вернули оригинал',
    extEditOn: 'Щёлкните по тексту, чтобы поправить',
    extEditOff: 'Правка выключена',
    extOutlinesOn: 'Контуры включены',
    extOutlinesOff: 'Контуры выключены',
    extInExtension: '«{0}» работает на настоящих страницах в расширении',
    extNoteTitle: 'Заметка к странице',
    extNotePlaceholder: 'Напишите то, что хотите найти здесь в следующий раз…',
    extNoteSaved: 'Сохранено для этой страницы',
    extLinkTitle: 'Чистая ссылка',
    extTrackers: 'Убрано трекеров: {0}',
    extCopyLink: 'Скопировать ссылку',
    extCopyMd: 'Скопировать Markdown',
    extStop: 'Готово',
    extEsc: 'Esc',

    cmdPlaceholder: 'Приложения, окна, буфер, расчёты — попробуйте «10 км в мили»',
    cmdCalc: 'Калькулятор',
    cmdConvert: 'Перевод величин',
    cmdApps: 'Приложения',
    cmdWindows: 'Окна',
    cmdClipboard: 'Буфер',
    cmdMenu: 'Панель',
    cmdLayout: 'Не та раскладка · ищу «{0}»',
    cmdWeb: 'Искать в интернете «{0}»',
    cmdHint: '↩ Открыть · esc Закрыть',
    cmdOpening: 'Открываю {0}',
    cmdRates: 'Примерный курс · приложение скачивает курсы каждый день',
    cmdEmpty: 'Ничего не нашлось',
    apps: ['Safari', 'Терминал', 'Cursor', 'Xcode', 'Музыка', 'Календарь', 'Заметки', 'Почта', 'Finder', 'Системные настройки', 'Visual Studio Code', 'Мониторинг системы'],

    clipTitle: 'Буфер',
    clipSearch: 'Поиск по истории',
    clipHint: '↩ Вставить · ⇧↩ Вставить без форматирования',
    clipPasted: 'Вставлено',
    clipPlain: 'Вставлено без форматирования',
    clipEmpty: 'Ничего не подходит',
    clipFromPage: 'Скопировано на этой странице',
    clipKinds: { text: 'Текст', link: 'Ссылка', color: 'Цвет', file: 'Файл', image: 'Картинка' },

    guideTitle: 'Всё, что он умеет, простыми словами.',
    guideLead: 'SAVISUL — одно нативное приложение для Mac вместо пачки мелких утилит. Без аккаунта и без подписки.',
    showMe: 'Показать',
    plateRest: 'В покое',
    plateEvent: 'Событие',
    plateHover: 'При наведении',
    snapNames: { left: 'Левая половина', left23: 'Две трети слева', left13: 'Треть слева', right: 'Правая половина', right23: 'Две трети справа', right13: 'Треть справа', max: 'Почти весь экран', restore: 'Как было' },
    plateTry: 'Попробуйте: 2+2, 10 км в мили, 100 $ в евро, ыфафкш',

    islandTitle: 'Вырез просыпается.',
    islandBody: 'В покое островок — тонкая полоска вокруг камеры. Наведите на него, и он раскроется на четыре вкладки. События открывают его сами и сами закрывают: агент закончил, подключили зарядку, сняли наушники, заглушили микрофон, файл скачался.',
    islandRows: [
      ['music', 'Музыка', 'Обложка, управление и текст песни, подтянутый к строке. Эквалайзер строится по звуку этого приложения.'],
      ['calendar', 'Календарь и таймеры', 'Ближайшая встреча видна заранее, за пять минут приходит напоминание. Таймер на 1, 5, 10 или 25 минут.'],
      ['sparkle', 'ИИ-агенты', 'Claude Code, Codex, Cursor, OpenCode и Copilot: кто работает, над каким проектом и на какой модели, сколько токенов и кода сегодня, когда сбросится лимит. Отсюда же можно дать любому из них новую задачу.'],
      ['tray', 'Файлы и камера', 'Полка для файлов, с которыми вы ещё не закончили, свежие загрузки и зеркало камеры перед звонком. Ничего не записывается.'],
      ['loop', 'Живые активности', 'Долгая работа — автоматизация, распознавание текста, конвертация, запрос к ИИ — ждёт вокруг камеры с кольцом и процентом.']
    ],
    islandAction: 'Открыть островок',

    soundTitle: 'У каждого приложения свой звук.',
    soundBody: 'Громкость Mac одна на всех. SAVISUL добавляет вторую: у каждой программы свой уровень, свой выход и свой потолок. Тихое видео можно поднять до 160%, а музыку оставить в колонках, пока звонок идёт в гарнитуру.',
    soundKeys: [
      ['⌃⌥O', 'Переключить весь Mac на следующее устройство вывода'],
      ['⌃⌥M', 'Заглушить все микрофоны и держать их тихими'],
      ['icon:headphones', 'Наушники пропали? Громкость опустится раньше, чем звук услышит комната']
    ],
    soundAction: 'Открыть «Звук» в панели',

    windowsTitle: 'Окна садятся, куда нужно.',
    windowsBody: '⌥Tab показывает приложения с живыми превью окон. Перетащите окно к краю — оно встанет в половину или в угол. Случайный ⌘Q больше не закрывает программу: клавишу нужно удержать или нажать дважды.',
    windowsKeys: [
      ['⌥Tab', 'Переключатель с живыми превью; Q, W, M и H действуют на окно'],
      ['⌃⌥← ⌃⌥→', 'Левая или правая половина; повтор — две трети, потом треть'],
      ['⌃⌥↩', 'Почти весь экран'],
      ['⌃⌥⌫', 'Вернуть как было'],
      ['⌃⌘ + перетаскивание', 'Левая кнопка двигает окно, правая тянет угол']
    ],
    windowsAction: 'Поставить заметку влево',

    clipTitleGuide: 'Помнит. Ищет. Считает.',
    clipBody: 'История хранит до тысячи записей: текст, ссылки, картинки, файлы и цвета. Рядом одно поле, которое ищет по приложениям, окнам, файлам, буферу и меню программы впереди, и ещё умеет считать.',
    clipKeys: [
      ['⌃⌥V', 'История буфера; ↩ вставляет, ⇧↩ вставляет без форматирования'],
      ['⌥Space', 'Командная строка: «2+2», «10 км в мили», «100 $ в евро»'],
      ['icon:keyboard', 'Не та раскладка? «ыфафкш» всё равно найдёт Safari'],
      ['⌃⌥R', 'Удержите — вокруг курсора встанет кольцо из восьми действий'],
      ['icon:tray', 'Встряхните файл при перетаскивании — появится полка']
    ],
    clipAction: 'Открыть командную строку',

    actionsTitle: 'Выделите что угодно. Нажмите ⌃⌥A.',
    actionsBody: 'Текст, ссылку, картинку или файлы в любом приложении: SAVISUL читает выделенное и предлагает только то, что к нему подходит. Ничего не выделено — работает с буфером обмена. Те же действия запускаются из командной строки, с полки и в автоматизациях.',
    actionsKeys: [
      ['⌃⌥A', 'Действия с выделенным в любом приложении; ↩ — выполнить, ⌘1–9 — быстрый выбор'],
      ['icon:image', 'Картинки: распознать текст прямо на Mac, закрепить поверх окон, конвертировать в PNG, JPEG или HEIC, сжать'],
      ['icon:link', 'Ссылки: убрать трекинговые метки, сделать QR-код, пересказать страницу'],
      ['icon:folder', 'Файлы: ZIP, переименовать пачкой, переместить, поделиться, скопировать путь'],
      ['icon:sparkle', 'ИИ: пересказать, перевести, переписать, объяснить или спросить — на вашем API-ключе']
    ],
    actionsAI: 'ИИ',
    ctxKinds: [
      { label: 'Текст', icon: 'type', head: 'Текст · 45 симв.', sample: 'SAVISUL превращает чёлку в живой островок.', actions: [
        ['sparkle', 'Кратко пересказать', true, 'Работает на вашем API-ключе (Anthropic, OpenAI, Gemini, Ollama и другие). Без ключа ничего никуда не уходит.'],
        ['translate', 'Перевести', true, 'На язык приложения; если текст уже на нём — на английский. Ваш ключ, ваш сервис.'],
        ['pencil', 'Переписать лучше', true, 'Яснее, в том же тоне и на том же языке — ⌘↩ вставит на место выделения.'],
        ['hash', 'Посчитать слова', false, 'Слов: 6 · Символов: 45 · Строк: 1'],
        ['qr', 'QR-код', false, 'QR-код закреплён поверх всех окон. Колёсиком — размер, двойной щелчок — закрыть.'],
        ['tray', 'Положить на полку', false, 'На полке.']
      ] },
      { label: 'Ссылка', icon: 'link', head: 'Ссылка · shop.example', sample: 'https://shop.example/item?id=7&utm_source=mail&fbclid=Xz', actions: [
        ['globe', 'Открыть в браузере', false, 'Открыто в браузере по умолчанию.'],
        ['sparkle', 'Очистить ссылку', false, 'https://shop.example/item?id=7 · убрано меток: 2 · скопировано'],
        ['page', 'Пересказать страницу', true, 'Читает страницу и пересказывает её на вашем API-ключе.'],
        ['qr', 'QR-код', false, 'QR-код закреплён поверх всех окон.']
      ] },
      { label: 'Картинка', icon: 'image', head: 'Картинка · 1440×900', sample: 'чек.png', actions: [
        ['type', 'Распознать текст', false, 'КОФЕЙНЯ НОРД · Флэт уайт 290 · Круассан 180 · Итого 470 — распознано на Mac, никуда не отправлено.'],
        ['pin', 'Закрепить на экране', false, 'Закреплено поверх всех окон. Можно перетащить куда угодно.'],
        ['refresh', 'Конвертировать в JPEG', false, 'чек.jpg · 312 КБ, рядом с оригиналом'],
        ['archive', 'Сжать картинку', false, '1,8 МБ → 412 КБ · чек (сжато).jpg']
      ] },
      { label: 'Файлы', icon: 'folder', head: 'Объектов: 3', sample: 'IMG_0412.heic, IMG_0413.heic, IMG_0414.heic', actions: [
        ['archive', 'Сжать в ZIP', false, 'Archive.zip · 9,6 МБ, рядом с фото'],
        ['pencil', 'Переименовать…', false, 'Поездка 1.heic, Поездка 2.heic, Поездка 3.heic'],
        ['folder', 'Переместить в…', false, 'Выберите папку — и файлы переедут туда.'],
        ['send', 'Поделиться…', false, 'AirDrop, Сообщения, Почта и всё остальное из меню «Поделиться».']
      ] }
    ],
    ctxPick: 'Выберите действие',

    autoTitle: 'Когда это — сделай то.',
    autoBody: 'Автоматизации следят за событиями на Mac и сами выполняют шаги, даже при закрытой панели. Ход каждого запуска виден вокруг чёлки, а если шаг не удался — видно почему.',
    autoRows: [
      ['headphones', 'Когда', 'Подключились или отключились наушники, в папке появился файл, открылось или закрылось приложение, ИИ-агент закончил, батарея ниже порога, подключили зарядку, наступило заданное время.'],
      ['sliders', 'Если', 'Уровень батареи, на зарядке или нет, открыто приложение, промежуток времени, дни недели, текущий выход звука.'],
      ['play', 'Сделать', 'Громкость и выход звука, микрофоны, открыть или закрыть приложение, быстрая команда, любая функция или действие SAVISUL, переименовать и переместить файл, полка, сообщение в островке.'],
      ['sparkle', 'Живые активности', 'Всё, что занимает время — автоматизация, распознавание текста, конвертация, запрос к ИИ, — показывает кольцо и процент вокруг чёлки.']
    ],
    autoAction: 'Открыть автоматизации в панели',
    autoWhen: 'Когда',
    autoIf: 'Если',
    autoDo: 'Сделать',
    autoRun: 'Запустить',
    autoRunning: 'Выполняется…',
    autoDone: 'Готово',
    autoTemplates: [
      { label: 'AirPods', icon: 'headphones', when: 'Подключились AirPods', cond: '', steps: ['Переключить звук на AirPods', 'Громкость 35%', 'Показать «AirPods · 35%» в островке'], done: 'AirPods · 35%' },
      { label: 'PDF', icon: 'page', when: 'В Загрузках появился PDF', cond: '', steps: ['Переименовать в «2026-10-07 счёт.pdf»', 'Переместить в Документы/PDF', 'Положить на полку'], done: '2026-10-07 счёт.pdf' },
      { label: 'Агент', icon: 'sparkle', when: 'ИИ-агент закончил', cond: 'Работал дольше минуты', steps: ['Показать «Codex · SAVISUL»', 'Проиграть звук «Glass»', 'Открыть Cursor'], done: 'Codex · SAVISUL' },
      { label: 'Батарея', icon: 'battery', when: 'Батарея ниже 20%', cond: 'Работает от батареи', steps: ['Выключить эквалайзер', 'Выключить текст песен', 'Предупредить в островке'], done: 'Батарея 19% · тяжёлые функции выключены' }
    ],

    chromeTitle: 'Та же чёлка на каждом сайте.',
    chromeBody: 'Расширение ставит чёлку наверху любого сайта. Наведите к верхнему краю или нажмите ⌥⇧N: чтение, тёмная тема, пипетка, линейка, инспектор CSS, перевод, заметки к странице, снимок всей страницы, чистые ссылки с QR-кодом и выгрузка данных. А в боковой панели — вкладки, сессии, закладки и ИИ.',
    chromeRows: [
      ['download', 'Идёт вместе с приложением', 'SAVISUL сам откроет страницу расширений браузера и папку расширения. Включите режим разработчика, нажмите «Загрузить распакованное» и выберите папку. Один раз.'],
      ['globe', 'Любой браузер на Chromium', 'Chrome, Edge, Brave, Opera, Vivaldi и Яндекс Браузер.'],
      ['laptop', 'Дружит с вашим Mac', 'Пока приложение запущено, чёлка на странице показывает крышку, сон, громкость и батарею, а расширение говорит на языке приложения.']
    ],
    chromeAction: 'Открыть браузер',

    panelTitle: 'И сам Mac — в одной панели.',
    panelBody: '⌃⌥S открывает панель для самого компьютера: на русском, английском, украинском или французском.',
    panelRows: [
      ['bolt', 'Питание', 'Режим закрытой крышки не даёт Mac уснуть. Видно батарею, адаптер и то, что держит сон.'],
      ['cpu', 'Система', 'Процессор, давление памяти, температура и какие программы тяжелее остальных. Управление вентиляторами: авто, умный режим, максимум или вручную — всегда в пределах самих вентиляторов, а выше 95 °C на полную.'],
      ['code', 'Работа', 'Сколько времени сегодня и за неделю ушло в редакторы и ИИ-приложения, сколько вы напечатали и что сделал ИИ в VS Code и Cursor: модель, токены, добавленные строки и новые файлы. Только счётчики, без текста.'],
      ['grid', 'Инструменты', 'Автоматизации, снимок области, окна или экрана, запись экрана, оповещения, когда датчик переходит ваш порог, и свои команды.']
    ],
    panelAction: 'Открыть панель',

    privacyTitle: 'Остаётся на вашем Mac.',
    privacyLead: 'Без аккаунта, без аналитики, без рекламы и телеметрии. Настройки, история буфера, заметки и статистика лежат в вашей папке пользователя. Вот единственные случаи, когда SAVISUL выходит в интернет.',
    privacyHead: ['Когда', 'Что уходит с Mac', 'Куда'],
    privacyRows: [
      ['Начинает играть песня', 'Название, исполнитель, альбом и длительность — чтобы найти текст', 'lrclib.net'],
      ['Вы переводите валюту в командной строке', 'Ничего о вас: скачиваются курсы на день', 'open.er-api.com'],
      ['Вы выбираете «Искать в интернете»', 'Ваш запрос, в вашем же браузере', 'Google'],
      ['Вы пользуетесь ИИ в расширении со своим ключом', 'Текст страницы и ваш вопрос', 'Anthropic'],
      ['Вы запускаете ИИ-действие со своим ключом', 'Выделенный текст, страница или картинка и ваш вопрос', 'Выбранный вами сервис'],
      ['Chrome не может перевести на устройстве', 'Адрес страницы, в новой вкладке', 'Google Переводчик']
    ],
    privacyLink: 'Читать политику конфиденциальности',

    installTitle: 'Установка за минуту.',
    installSteps: [
      ['Скачайте образ диска', 'Откройте его двойным щелчком и перетащите SAVISUL в «Программы». В архиве ZIP то же приложение.'],
      ['Откройте', 'Сборка подписана на нашем компьютере, а не заверена Apple, поэтому macOS может остановить первый запуск. Откройте Системные настройки → Конфиденциальность и безопасность и нажмите «Всё равно открыть» — или запустите скрипт из «Если не открывается.txt».'],
      ['Разрешите только нужное', 'Каждое разрешение спрашивается, когда оно понадобится функции.'],
      ['Добавьте чёлку в браузер', 'SAVISUL сам откроет страницу расширений и папку. Режим разработчика → «Загрузить распакованное» → выберите папку.']
    ],
    permissions: [
      ['Запись экрана', 'живые превью окон'],
      ['Захват звука', 'громкость по приложениям'],
      ['Универсальный доступ', 'окна, меню и Dock'],
      ['Календарь, камера, «Загрузки»', 'только когда вы их включите']
    ],
    installHelp: 'Если не открывается.txt',

    openTitle: 'Открытый код и честное авторство.',
    openLead: 'SAVISUL выпущен под лицензией Apache 2.0. Пользуйтесь, меняйте, выпускайте свои сборки, в том числе в коммерческих целях. Если вы распространяете SAVISUL или продукт на его основе, сохраните файл NOTICE и укажите происхождение.',
    openMayTitle: 'Можно',
    openMay: ['Пользоваться дома и в работе, в том числе коммерчески', 'Менять код и публиковать изменения', 'Распространять и продавать свои сборки'],
    openMustTitle: 'Нужно',
    openMust: ['Приложить лицензию и файл NOTICE', 'Указать SAVISUL в окне «О программе» или в документации', 'Отметить файлы, которые вы изменили', 'Взять своё название и логотип: «SAVISUL» не лицензируется'],
    creditLabel: 'Строка авторства',
    creditLine: 'Based on SAVISUL by The SAVISUL Authors · Apache License 2.0',
    copyCredit: 'Скопировать',
    copied: 'Скопировано',
    readLicense: 'Читать лицензию',
    viewGithub: 'Открыть на GitHub',

    finalTitle: 'Пусть вырез работает.',
    finalZip: 'Архив ZIP',
    finalQuestions: 'Вопросы и идеи: {0}',

    footerRights: '© {0} The SAVISUL Authors',
    footerPrivacy: 'Приватность',
    footerLicense: 'Лицензия',
    footerContact: 'Почта',
    footerTrademarks: 'Не связаны с Apple Inc. и Google LLC. Mac, MacBook и macOS — товарные знаки Apple Inc. Chrome — товарный знак Google LLC.',
    langName: 'Русский',

    docUpdated: 'Обновлено {0}',
    docBack: 'Назад к SAVISUL',
    docContents: 'На этой странице',
    notFoundTitle: 'Такого окна нет.',
    notFoundBody: 'Страницы, которую вы открыли, здесь нет. Возможно, она переехала или её не было.',
    notFoundHome: 'На главную SAVISUL'
  }
};

export const LANGS = ['en', 'ru'];
const KEY = 'savisul-site-lang';
const listeners = new Set();

function initial() {
  const fromUrl = new URLSearchParams(location.search).get('lang');
  if (LANGS.includes(fromUrl)) return fromUrl;
  try {
    const saved = localStorage.getItem(KEY);
    if (LANGS.includes(saved)) return saved;
  } catch {}
  return 'en';
}

export let lang = initial();

export function t(key, ...args) {
  const value = STRINGS[lang][key] ?? STRINGS.en[key] ?? key;
  if (typeof value !== 'string') return value;
  return args.length ? value.replace(/\{(\d+)\}/g, (_, i) => args[Number(i)] ?? '') : value;
}

export function apply(root = document) {
  document.documentElement.lang = lang;
  document.documentElement.dataset.lang = lang;
  for (const el of root.querySelectorAll('[data-i18n]')) {
    const args = el.dataset.i18nArgs ? JSON.parse(el.dataset.i18nArgs) : [];
    el.textContent = t(el.dataset.i18n, ...args);
  }
  for (const el of root.querySelectorAll('[data-i18n-attr]')) {
    for (const pair of el.dataset.i18nAttr.split(';')) {
      const [attr, key] = pair.split(':');
      el.setAttribute(attr, t(key));
    }
  }
}

export function setLang(next) {
  if (!LANGS.includes(next) || next === lang) return;
  lang = next;
  try { localStorage.setItem(KEY, next); } catch {}
  const url = new URL(location.href);
  if (url.searchParams.has('lang')) {
    url.searchParams.set('lang', next);
    history.replaceState(null, '', url);
  }
  apply();
  for (const listener of listeners) listener(lang);
}

export const onLang = (listener) => listeners.add(listener);
