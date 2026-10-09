import Foundation

/// A line of interface text in every app language, kept next to the feature that shows it.
struct Phrase: Hashable, Sendable {
    let en: String
    let ru: String
    let uk: String
    let fr: String

    init(_ en: String, ru: String, uk: String, fr: String) {
        self.en = en
        self.ru = ru
        self.uk = uk
        self.fr = fr
    }

    func text(_ language: Language) -> String {
        switch language {
        case .en: en
        case .ru: ru
        case .uk: uk
        case .fr: fr
        }
    }

    /// Reading the language through the suite lets SwiftUI views redraw when it changes.
    @MainActor var text: String { text(Suite.shared.language) }

    @MainActor func callAsFunction(_ arguments: CVarArg...) -> String {
        let language = Suite.shared.language
        return String(format: text(language), locale: language.locale, arguments: arguments)
    }
}

@MainActor
enum Say {
    static func duration(_ seconds: Double) -> String { L10n.duration(seconds, Suite.shared.language) }

    /// "4:07" or "1:02:45" for running clocks.
    static func clock(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let rest = total % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, rest) : String(format: "%d:%02d", minutes, rest)
    }

    static func number(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Suite.shared.language.locale
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    /// 1.2k, 34k, 5.6M — token counts that fit in a notch.
    static func compact(_ value: Int) -> String {
        let number = Double(value)
        let language = Suite.shared.language
        let (k, m, b) = switch language {
        case .ru: ("тыс", "млн", "млрд")
        case .uk: ("тис", "млн", "млрд")
        case .fr: ("k", "M", "Md")
        case .en: ("k", "M", "B")
        }
        func trimmed(_ x: Double) -> String {
            let formatter = NumberFormatter()
            formatter.locale = language.locale
            formatter.maximumFractionDigits = x < 10 ? 1 : 0
            formatter.minimumFractionDigits = 0
            return formatter.string(from: NSNumber(value: x)) ?? String(format: "%.1f", x)
        }
        let space = language == .en ? "" : "\u{202F}"
        switch number {
        case 1_000_000_000...: return "\(trimmed(number / 1_000_000_000))\(space)\(b)"
        case 1_000_000...: return "\(trimmed(number / 1_000_000))\(space)\(m)"
        case 10_000...: return "\(trimmed(number / 1_000))\(space)\(k)"
        default: return Self.number(value)
        }
    }

    static func percent(_ value: Double) -> String {
        let rounded = Int(value.rounded())
        return Suite.shared.language == .fr ? "\(rounded)\u{202F}%" : "\(rounded)%"
    }

    static func money(_ dollars: Double) -> String {
        dollars >= 100 ? String(format: "$%.0f", dollars) : String(format: "$%.2f", dollars)
    }

    static func bytes(_ count: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        return formatter.string(fromByteCount: count)
    }

    static func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Suite.shared.language.locale
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    /// "через 12 мин", "in 2 h 5 m".
    static func relative(_ seconds: Double) -> String {
        Phrases.inTime(duration(max(seconds, 60)))
    }

    /// "5 мин назад", "вчера", "2 h ago".
    static func ago(_ date: Date) -> String {
        if Date().timeIntervalSince(date) < 45 { return Phrases.now.text }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Suite.shared.language.locale
        formatter.unitsStyle = .short
        formatter.dateTimeStyle = .named
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

/// Phrases shared by several features.
enum Phrases {
    static let inTimeFormat = Phrase("in %@", ru: "через %@", uk: "через %@", fr: "dans %@")
    @MainActor static func inTime(_ value: String) -> String { inTimeFormat(value) }

    static let open = Phrase("Open", ru: "Открыть", uk: "Відкрити", fr: "Ouvrir")
    static let reveal = Phrase("Show in Finder", ru: "Показать в Finder", uk: "Показати у Finder", fr: "Afficher dans le Finder")
    static let copy = Phrase("Copy", ru: "Скопировать", uk: "Скопіювати", fr: "Copier")
    static let remove = Phrase("Remove", ru: "Убрать", uk: "Прибрати", fr: "Retirer")
    static let clear = Phrase("Clear", ru: "Очистить", uk: "Очистити", fr: "Effacer")
    static let cancel = Phrase("Cancel", ru: "Отмена", uk: "Скасувати", fr: "Annuler")
    static let allow = Phrase("Allow", ru: "Разрешить", uk: "Дозволити", fr: "Autoriser")
    static let openSettings = Phrase("Open Settings", ru: "Открыть настройки", uk: "Відкрити налаштування", fr: "Ouvrir les réglages")
    static let done = Phrase("Done", ru: "Готово", uk: "Готово", fr: "Terminé")
    static let now = Phrase("now", ru: "сейчас", uk: "зараз", fr: "maintenant")
    static let today = Phrase("Today", ru: "Сегодня", uk: "Сьогодні", fr: "Aujourd’hui")
    static let tomorrow = Phrase("Tomorrow", ru: "Завтра", uk: "Завтра", fr: "Demain")
    static let needsAccessibility = Phrase(
        "Needs Accessibility access for SAVISUL.",
        ru: "Нужен доступ SAVISUL к универсальному доступу.",
        uk: "Потрібен доступ SAVISUL до Універсального доступу.",
        fr: "SAVISUL a besoin de l’accès Accessibilité.")
    static let needsScreen = Phrase(
        "Live previews need Screen Recording access.",
        ru: "Живым превью нужен доступ к записи экрана.",
        uk: "Живим превʼю потрібен доступ до запису екрана.",
        fr: "Les aperçus en direct ont besoin de l’enregistrement de l’écran.")
}
