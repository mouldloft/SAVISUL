import Foundation
import SwiftUI

// WHEN → IF → DO. One automation is a trigger, optional conditions and a list of steps. The shapes are flat on
// purpose: a kind plus a few plain fields, so they save as simple JSON and one editor row can show any of them.

struct Automation: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var enabled = true
    var trigger: AutomationTrigger
    var conditions: [AutomationCondition] = []
    var steps: [AutomationStep] = []
    /// Shows its progress around the notch while it runs.
    var showInIsland = true
    var lastRun: Date?
    var runs = 0
}

struct AutomationTrigger: Codable, Equatable {
    enum Kind: String, Codable, CaseIterable {
        case deviceConnected, deviceDisconnected, fileAdded, appLaunched, appQuit, agentFinished
        case batteryBelow, powerConnected, powerDisconnected, schedule
    }

    var kind: Kind
    /// Device name filter, folder path, app bundle id or agent ("" means any).
    var text = ""
    /// What to show for `text`: the app's or agent's name.
    var label = ""
    /// File types for a folder, "pdf, jpg"; empty means every file.
    var extensions = ""
    /// Battery percent, or minutes after midnight for a schedule.
    var number = 20
    /// Schedule days, 1 = Monday … 7 = Sunday; empty means every day.
    var weekdays: [Int] = []
}

struct AutomationCondition: Codable, Equatable, Identifiable {
    enum Kind: String, Codable, CaseIterable {
        case batteryBelow, batteryAbove, onPower, onBattery, appRunning, appNotRunning, timeBetween, weekdays, outputIs
    }

    var id = UUID()
    var kind: Kind
    var text = ""
    var label = ""
    /// Percent, or the start of a time window in minutes after midnight.
    var number = 20
    /// The end of a time window.
    var number2 = 18 * 60
    var weekdays: [Int] = []
}

struct AutomationStep: Codable, Equatable, Identifiable {
    enum Kind: String, Codable, CaseIterable {
        case notice, sound, setVolume, switchOutput, muteMics, unmuteMics, openApp, quitApp, openURL, shortcut
        case feature, action, renameFile, moveFile, shelf, wait
    }

    var id = UUID()
    var kind: Kind
    /// Notice text, sound, output, bundle id, link, shortcut, feature id, action id, name pattern or folder.
    var text = ""
    var label = ""
    /// Volume percent or seconds to wait.
    var number = 35
    /// Feature on or off.
    var flag = false
}

/// What happened, handed to the steps: the file that appeared, the agent that finished, the device that connected.
struct AutomationEvent {
    var title: String
    var files: [URL] = []
    var text: String?
    /// Words for {placeholders} in notices: file, agent, project, device, battery.
    var values: [String: String] = [:]

    static let manual = AutomationEvent(title: "")
}

struct AutomationRecord: Identifiable {
    let id = UUID()
    let name: String
    let date: Date
    let ok: Bool
    let detail: String?
}

// MARK: Names and symbols

extension AutomationTrigger.Kind {
    var symbol: String {
        switch self {
        case .deviceConnected: "headphones"
        case .deviceDisconnected: "headphones.slash"
        case .fileAdded: "folder.badge.plus"
        case .appLaunched: "app.badge.checkmark"
        case .appQuit: "xmark.app"
        case .agentFinished: "sparkles"
        case .batteryBelow: "battery.25percent"
        case .powerConnected: "powerplug.fill"
        case .powerDisconnected: "powerplug"
        case .schedule: "clock"
        }
    }

    var title: Phrase {
        switch self {
        case .deviceConnected: Phrase("Audio device connects", ru: "Подключилось аудиоустройство", uk: "Підключено аудіопристрій", fr: "Un appareil audio se connecte")
        case .deviceDisconnected: Phrase("Audio device disconnects", ru: "Отключилось аудиоустройство", uk: "Відключено аудіопристрій", fr: "Un appareil audio se déconnecte")
        case .fileAdded: Phrase("File appears in a folder", ru: "В папке появился файл", uk: "У теці зʼявився файл", fr: "Un fichier arrive dans un dossier")
        case .appLaunched: Phrase("App opens", ru: "Открылось приложение", uk: "Відкрито застосунок", fr: "Une app s’ouvre")
        case .appQuit: Phrase("App quits", ru: "Закрылось приложение", uk: "Закрито застосунок", fr: "Une app se ferme")
        case .agentFinished: Phrase("AI agent finishes", ru: "ИИ-агент закончил", uk: "ШІ-агент завершив", fr: "Un agent IA termine")
        case .batteryBelow: Phrase("Battery drops below", ru: "Батарея ниже", uk: "Батарея нижче", fr: "Batterie sous")
        case .powerConnected: Phrase("Charger connected", ru: "Подключили зарядку", uk: "Підключено зарядку", fr: "Chargeur branché")
        case .powerDisconnected: Phrase("Charger disconnected", ru: "Отключили зарядку", uk: "Відключено зарядку", fr: "Chargeur débranché")
        case .schedule: Phrase("At a time", ru: "В заданное время", uk: "У заданий час", fr: "À une heure")
        }
    }
}

extension AutomationCondition.Kind {
    var title: Phrase {
        switch self {
        case .batteryBelow: Phrase("Battery below", ru: "Батарея ниже", uk: "Батарея нижче", fr: "Batterie sous")
        case .batteryAbove: Phrase("Battery above", ru: "Батарея выше", uk: "Батарея вище", fr: "Batterie au-dessus de")
        case .onPower: Phrase("On charger", ru: "На зарядке", uk: "На зарядці", fr: "Sur secteur")
        case .onBattery: Phrase("On battery", ru: "От батареи", uk: "Від батареї", fr: "Sur batterie")
        case .appRunning: Phrase("App is open", ru: "Приложение открыто", uk: "Застосунок відкрито", fr: "L’app est ouverte")
        case .appNotRunning: Phrase("App isn’t open", ru: "Приложение не открыто", uk: "Застосунок не відкрито", fr: "L’app n’est pas ouverte")
        case .timeBetween: Phrase("Time between", ru: "Время между", uk: "Час між", fr: "Heure entre")
        case .weekdays: Phrase("On days", ru: "По дням", uk: "За днями", fr: "Certains jours")
        case .outputIs: Phrase("Sound plays through", ru: "Звук идёт через", uk: "Звук іде через", fr: "Le son sort par")
        }
    }

    var symbol: String {
        switch self {
        case .batteryBelow, .batteryAbove: "battery.50percent"
        case .onPower: "powerplug.fill"
        case .onBattery: "battery.75percent"
        case .appRunning, .appNotRunning: "app"
        case .timeBetween: "clock"
        case .weekdays: "calendar"
        case .outputIs: "speaker.wave.2"
        }
    }
}

extension AutomationStep.Kind {
    var title: Phrase {
        switch self {
        case .notice: Phrase("Show in the island", ru: "Показать в островке", uk: "Показати в острівці", fr: "Afficher dans l’îlot")
        case .sound: Phrase("Play a sound", ru: "Проиграть звук", uk: "Відтворити звук", fr: "Jouer un son")
        case .setVolume: Phrase("Set volume", ru: "Громкость", uk: "Гучність", fr: "Régler le volume")
        case .switchOutput: Phrase("Switch sound output", ru: "Переключить выход звука", uk: "Перемкнути вихід звуку", fr: "Changer de sortie audio")
        case .muteMics: Phrase("Mute microphones", ru: "Выключить микрофоны", uk: "Вимкнути мікрофони", fr: "Couper les micros")
        case .unmuteMics: Phrase("Turn microphones on", ru: "Включить микрофоны", uk: "Увімкнути мікрофони", fr: "Activer les micros")
        case .openApp: Phrase("Open app", ru: "Открыть приложение", uk: "Відкрити застосунок", fr: "Ouvrir une app")
        case .quitApp: Phrase("Quit app", ru: "Закрыть приложение", uk: "Закрити застосунок", fr: "Quitter une app")
        case .openURL: Phrase("Open a link", ru: "Открыть ссылку", uk: "Відкрити посилання", fr: "Ouvrir un lien")
        case .shortcut: Phrase("Run a Shortcut", ru: "Запустить быструю команду", uk: "Запустити швидку команду", fr: "Lancer un raccourci")
        case .feature: Phrase("Turn a SAVISUL feature on/off", ru: "Вкл/выкл функцию SAVISUL", uk: "Увімк/вимк функцію SAVISUL", fr: "Activer/couper une fonction SAVISUL")
        case .action: Phrase("Run an action", ru: "Выполнить действие", uk: "Виконати дію", fr: "Lancer une action")
        case .renameFile: Phrase("Rename the file", ru: "Переименовать файл", uk: "Перейменувати файл", fr: "Renommer le fichier")
        case .moveFile: Phrase("Move the file", ru: "Переместить файл", uk: "Перемістити файл", fr: "Déplacer le fichier")
        case .shelf: Phrase("Add to Shelf", ru: "Положить на полку", uk: "Покласти на полицю", fr: "Mettre sur l’étagère")
        case .wait: Phrase("Wait", ru: "Подождать", uk: "Зачекати", fr: "Attendre")
        }
    }

    var symbol: String {
        switch self {
        case .notice: "capsule.inset.filled"
        case .sound: "bell.fill"
        case .setVolume: "speaker.wave.2.fill"
        case .switchOutput: "arrow.triangle.swap"
        case .muteMics: "mic.slash.fill"
        case .unmuteMics: "mic.fill"
        case .openApp: "arrow.up.forward.app"
        case .quitApp: "xmark.app"
        case .openURL: "link"
        case .shortcut: "square.stack.3d.up.fill"
        case .feature: "switch.2"
        case .action: "wand.and.rays"
        case .renameFile: "character.cursor.ibeam"
        case .moveFile: "folder"
        case .shelf: "tray.and.arrow.down"
        case .wait: "hourglass"
        }
    }

    /// Steps that work on the file a folder trigger found.
    var needsFile: Bool { self == .renameFile || self == .moveFile }
}

// MARK: Templates

enum AutomationTemplates {
    static let cursor = "com.todesktop.230313mzl4w4u92"

    @MainActor static var all: [Automation] {
        let downloads = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads").path
        let documents = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents/PDF").path
        return [
            Automation(name: Phrase("AirPods connected", ru: "Подключились AirPods", uk: "Підключено AirPods", fr: "AirPods connectés").text,
                       trigger: AutomationTrigger(kind: .deviceConnected, text: "AirPods"),
                       steps: [AutomationStep(kind: .switchOutput, text: "AirPods"), AutomationStep(kind: .setVolume, number: 35),
                               AutomationStep(kind: .notice, text: "{device} · 35%")]),
            Automation(name: Phrase("PDF in Downloads", ru: "PDF в Загрузках", uk: "PDF у Завантаженнях", fr: "PDF dans Téléchargements").text,
                       trigger: AutomationTrigger(kind: .fileAdded, text: downloads, extensions: "pdf"),
                       steps: [AutomationStep(kind: .renameFile, text: "{date} {name}"), AutomationStep(kind: .moveFile, text: documents),
                               AutomationStep(kind: .shelf), AutomationStep(kind: .notice, text: "{file}")]),
            Automation(name: Phrase("Zoom meeting", ru: "Встреча в Zoom", uk: "Зустріч у Zoom", fr: "Réunion Zoom").text,
                       trigger: AutomationTrigger(kind: .appLaunched, text: "us.zoom.xos", label: "zoom.us"),
                       steps: [AutomationStep(kind: .unmuteMics), AutomationStep(kind: .setVolume, number: 60),
                               AutomationStep(kind: .shortcut, text: Phrase("Do Not Disturb", ru: "Не беспокоить", uk: "Не турбувати", fr: "Ne pas déranger").text),
                               AutomationStep(kind: .notice, text: Phrase("Meeting mode", ru: "Режим встречи", uk: "Режим зустрічі", fr: "Mode réunion").text)]),
            Automation(name: Phrase("Agent finished", ru: "Агент закончил", uk: "Агент завершив", fr: "Agent terminé").text,
                       trigger: AutomationTrigger(kind: .agentFinished),
                       steps: [AutomationStep(kind: .notice, text: "{agent} · {project}"), AutomationStep(kind: .sound, text: "Glass"),
                               AutomationStep(kind: .openApp, text: cursor, label: "Cursor")]),
            Automation(name: Phrase("Battery below 20%", ru: "Батарея ниже 20%", uk: "Батарея нижче 20%", fr: "Batterie sous 20 %").text,
                       trigger: AutomationTrigger(kind: .batteryBelow, number: 20),
                       conditions: [AutomationCondition(kind: .onBattery)],
                       steps: [AutomationStep(kind: .feature, text: "islandEqualizer", flag: false),
                               AutomationStep(kind: .feature, text: "islandLyrics", flag: false),
                               AutomationStep(kind: .feature, text: "islandCamera", flag: false),
                               AutomationStep(kind: .notice, text: Phrase("Battery {battery} · heavy features off", ru: "Батарея {battery} · тяжёлые функции выключены",
                                                                         uk: "Батарея {battery} · важкі функції вимкнено", fr: "Batterie {battery} · fonctions lourdes coupées").text)])
        ]
    }
}
