import AppKit
import Carbon.HIToolbox
import SwiftUI

@MainActor
enum SuiteActions {
    static func action(_ id: String) -> SuiteAction? { all.first { $0.id == id } }

    static func run(_ id: String) {
        _ = ActionEngine.perform(id, in: all)
    }

    static var all: [SuiteAction] {
        let suite = Suite.shared
        var list: [SuiteAction] = [
            SuiteAction(id: "capture.area", title: Phrase("Capture area", ru: "Снимок области", uk: "Знімок області", fr: "Capturer une zone"),
                        symbol: "rectangle.dashed", tint: Palette.accent, keywords: ["screenshot", "скриншот", "снимок"]) {
                suite.app?.shoot(.selection)
            },
            SuiteAction(id: "capture.window", title: Phrase("Capture window", ru: "Снимок окна", uk: "Знімок вікна", fr: "Capturer une fenêtre"),
                        symbol: "macwindow", tint: Palette.accent, keywords: ["screenshot", "скриншот"]) {
                suite.app?.shoot(.window)
            },
            SuiteAction(id: "capture.screen", title: Phrase("Capture screen", ru: "Снимок экрана", uk: "Знімок екрана", fr: "Capturer l’écran"),
                        symbol: "display", tint: Palette.accent, keywords: ["screenshot", "скриншот"]) {
                suite.app?.shoot(.screen)
            },
            SuiteAction(id: "capture.record", title: Phrase("Record screen", ru: "Запись экрана", uk: "Запис екрана", fr: "Enregistrer l’écran"),
                        symbol: "record.circle", tint: Palette.danger, keywords: ["video", "видео", "запись"]) {
                suite.app?.toggleRecording()
            },
            SuiteAction(id: "clipboard.open", title: Phrase("Clipboard history", ru: "История буфера", uk: "Історія буфера", fr: "Historique du presse-papiers"),
                        symbol: "doc.on.clipboard", tint: Palette.accent, keywords: ["clipboard", "буфер", "paste"]) {
                suite.clipboard.panel.open()
            },
            SuiteAction(id: "shelf.open", title: Phrase("Shelf", ru: "Полка", uk: "Полиця", fr: "Étagère"),
                        symbol: "tray.full", tint: Palette.accent, keywords: ["shelf", "полка", "drop"]) {
                suite.clipboard.shelfPanel.toggle()
            },
            SuiteAction(id: "sound.mute", title: Phrase("Mute sound", ru: "Выключить звук", uk: "Вимкнути звук", fr: "Couper le son"),
                        symbol: "speaker.slash.fill", tint: Palette.ink, keywords: ["mute", "звук", "тишина"]) {
                guard let audio = suite.app?.audio, let device = audio.currentOutput else { return }
                let muted = !(device.muted ?? false)
                audio.setMuted(muted, device: device.id, scope: .output)
                suite.notify(IslandNotice(symbol: muted ? "speaker.slash.fill" : "speaker.wave.2.fill", tint: Palette.ink,
                                          title: muted ? MixerPhrases.off.text : device.name, detail: nil, duration: 1.6))
            },
            SuiteAction(id: "sound.output", title: MixerPhrases.nextOutput, symbol: "arrow.triangle.swap", tint: Palette.accent,
                        keywords: ["output", "speakers", "headphones", "выход", "колонки", "наушники"]) {
                suite.sound.cycleOutput()
            },
            SuiteAction(id: "mic.mute", title: MixerPhrases.muteMics, symbol: "mic.slash.fill", tint: Palette.danger,
                        keywords: ["microphone", "mic", "микрофон"]) {
                suite.sound.toggleMics()
            },
            SuiteAction(id: "display.off", title: Phrase("Turn display off", ru: "Погасить экран", uk: "Вимкнути екран", fr: "Éteindre l’écran"),
                        symbol: "moon.fill", tint: Palette.accent, keywords: ["sleep", "display", "экран", "сон"]) {
                DispatchQueue.global(qos: .userInitiated).async { _ = Shell.run("/usr/bin/pmset", ["displaysleepnow"], timeout: 5) }
            },
            SuiteAction(id: "screen.lock", title: Phrase("Lock screen", ru: "Заблокировать", uk: "Заблокувати", fr: "Verrouiller"),
                        symbol: "lock.fill", tint: Palette.ink, keywords: ["lock", "блок", "замок"]) {
                Keys.whenModifiersReleased { Keys.tap(CGKeyCode(kVK_ANSI_Q), flags: [.maskCommand, .maskControl]) }
            },
            SuiteAction(id: "command.open", title: Phrase("Command bar", ru: "Командная строка", uk: "Командний рядок", fr: "Barre de commande"),
                        symbol: "magnifyingglass", tint: Palette.accent, keywords: ["search", "поиск"]) {
                suite.commands.bar.open()
            },
            SuiteAction(id: "context.open", title: Phrase("Actions on the selection", ru: "Действия с выделенным", uk: "Дії з виділеним", fr: "Actions sur la sélection"),
                        symbol: "wand.and.rays", tint: Palette.accent, keywords: ["context", "selection", "ocr", "выделение", "действия"]) {
                suite.contextActions.open()
            },
            SuiteAction(id: "automations.open", title: Phrase("Automations", ru: "Автоматизации", uk: "Автоматизації", fr: "Automatisations"),
                        symbol: "point.3.filled.connected.trianglepath.dotted", tint: Palette.accent, keywords: ["automation", "workflow", "автоматизация", "сценарий"]) {
                suite.app?.select(.automations)
                suite.app?.onShow?()
            },
            SuiteAction(id: "quick.panel", title: Phrase("Favorites panel", ru: "Панель избранного", uk: "Панель вибраного", fr: "Panneau des favoris"),
                        symbol: "square.grid.2x2", tint: Palette.accent, keywords: ["favorites", "избранное"]) {
                suite.commands.quick.toggle()
            },
            SuiteAction(id: "music.toggle", title: Phrase("Play / pause", ru: "Пауза / играть", uk: "Пауза / грати", fr: "Lecture / pause"),
                        symbol: "playpause.fill", tint: Palette.positive, keywords: ["music", "музыка", "pause", "пауза"]) {
                suite.nowPlaying.toggle()
            },
            SuiteAction(id: "music.next", title: Phrase("Next track", ru: "Следующий трек", uk: "Наступний трек", fr: "Piste suivante"),
                        symbol: "forward.fill", tint: Palette.positive, keywords: ["music", "музыка", "next"]) {
                suite.nowPlaying.next()
            },
            SuiteAction(id: "island.toggle", title: Phrase("Dynamic Island on/off", ru: "Остров вкл/выкл", uk: "Острів увімк/вимк", fr: "Île on/off"),
                        symbol: "capsule.fill", tint: Palette.accent, keywords: ["island", "остров", "notch", "челка"]) {
                suite.settings.island.toggle()
            },
            SuiteAction(id: "island.agents", title: Phrase("AI agents", ru: "ИИ-агенты", uk: "ШІ-агенти", fr: "Agents IA"),
                        symbol: "sparkles", tint: AgentKind.codex.tint, keywords: ["codex", "claude", "cursor", "агенты", "лимиты"]) {
                suite.openIsland(.agents)
            },
            SuiteAction(id: "camera.mirror", title: Phrase("Camera mirror", ru: "Зеркало камеры", uk: "Дзеркало камери", fr: "Miroir caméra"),
                        symbol: "camera.fill", tint: Palette.accent, keywords: ["camera", "камера", "зеркало"]) {
                suite.openIsland(.camera)
            },
            SuiteAction(id: "dark.mode", title: Phrase("Toggle dark mode", ru: "Тёмная тема", uk: "Темна тема", fr: "Mode sombre"),
                        symbol: "circle.lefthalf.filled", tint: Palette.ink, keywords: ["dark", "light", "тема", "тёмная"]) {
                let script = "tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode"
                var error: NSDictionary?
                NSAppleScript(source: script)?.executeAndReturnError(&error)
            },
            SuiteAction(id: "lid.awake", title: Phrase("Stay awake with lid closed", ru: "Не спать с закрытой крышкой", uk: "Не спати із закритою кришкою", fr: "Rester éveillé capot fermé"),
                        symbol: "laptopcomputer", tint: Palette.accent, keywords: ["lid", "крышка", "сон", "awake"]) {
                suite.app?.toggleLid()
            },
            SuiteAction(id: "settings.open", title: Phrase("SAVISUL settings", ru: "Настройки SAVISUL", uk: "Налаштування SAVISUL", fr: "Réglages SAVISUL"),
                        symbol: "gearshape.fill", tint: Palette.secondary, keywords: ["settings", "настройки", "preferences"]) {
                suite.openSettings()
            }
        ]
        for minutes in [1, 5, 10, 25] {
            list.append(SuiteAction(id: "timer.\(minutes)", title: Phrase("Timer %d min", ru: "Таймер %d мин", uk: "Таймер %d хв", fr: "Minuteur %d min"),
                                    symbol: "timer", tint: Palette.warning, keywords: ["timer", "таймер", "\(minutes)"]) {
                suite.timers.add(minutes: Double(minutes))
                suite.notify(IslandNotice(symbol: "timer", tint: Palette.warning, title: Phrase("Timer %d min", ru: "Таймер %d мин", uk: "Таймер %d хв", fr: "Minuteur %d min")(minutes),
                                          detail: nil, style: .success, duration: 1.8))
            })
        }
        let snaps: [SnapAction] = [.left, .right, .maximize, .center, .nextDisplay, .restore]
        for snap in snaps {
            list.append(SuiteAction(id: "window.\(snap.rawValue)", title: snap.title, symbol: "rectangle.split.2x1", tint: Palette.accent,
                                    keywords: ["window", "окно"]) {
                suite.windows.snapper.perform(snap)
            })
        }
        return list
    }

    /// Titles with numbers in them ("Timer %d min") need the number filled in.
    static func title(_ action: SuiteAction) -> String {
        if action.id.hasPrefix("timer."), let minutes = Int(action.id.dropFirst(6)) { return action.title(minutes) }
        return action.title.text
    }
}
