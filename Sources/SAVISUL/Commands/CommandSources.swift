import AppKit
import Foundation

// MARK: Matching

enum Fuzzy {
    /// 0…100, or nil when the query does not match at all. Word starts and initials beat substrings.
    static func score(_ text: String, _ query: String) -> Double? {
        guard !query.isEmpty else { return nil }
        let t = text.lowercased()
        let q = query.lowercased()
        if t == q { return 100 }
        if t.hasPrefix(q) { return 92 - min(Double(t.count - q.count) * 0.15, 8) }
        let words = t.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        if words.contains(where: { $0.hasPrefix(q) }) { return 78 }
        if q.count >= 2 {
            let initials = String(words.compactMap(\.first))
            if initials.hasPrefix(q) { return 72 }
        }
        if t.contains(q) { return 62 }
        guard q.count >= 2 else { return nil }
        var iterator = t.makeIterator()
        var matched = 0
        var gaps = 0
        outer: for character in q {
            while let next = iterator.next() {
                if next == character {
                    matched += 1
                    continue outer
                }
                gaps += 1
            }
            break
        }
        guard matched == q.count else { return nil }
        return max(40 - Double(gaps) * 0.6, 12)
    }

    /// The same keys typed on the other keyboard layout: "ыфафкш" → "safari".
    static func otherLayout(_ text: String) -> String? {
        let ru = Array("йцукенгшщзхъфывапролджэячсмитьбю.ёЙЦУКЕНГШЩЗХЪФЫВАПРОЛДЖЭЯЧСМИТЬБЮ,Ё")
        let en = Array("qwertyuiop[]asdfghjkl;'zxcvbnm,./`QWERTYUIOP{}ASDFGHJKL:\"ZXCVBNM<>?~")
        var toEn: [Character: Character] = [:]
        var toRu: [Character: Character] = [:]
        for (r, e) in zip(ru, en) {
            toEn[r] = e
            toRu[e] = r
        }
        let hasCyrillic = text.contains { toEn[$0] != nil }
        let converted = String(text.map { hasCyrillic ? (toEn[$0] ?? $0) : (toRu[$0] ?? $0) })
        return converted == text ? nil : converted
    }
}

// MARK: Apps

struct AppRecord: Sendable {
    let name: String
    let fileName: String
    let path: String
    let bundleID: String?
}

/// Installed applications from the usual folders, read once and refreshed now and then.
@MainActor
final class AppIndex {
    static let shared = AppIndex()
    private(set) var apps: [AppRecord] = []
    private var scannedAt = Date.distantPast
    private var scanning = false

    func refresh() {
        guard !scanning, Date().timeIntervalSince(scannedAt) > 600 else { return }
        scanning = true
        DispatchQueue.global(qos: .userInitiated).async {
            let list = Self.scan()
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    AppIndex.shared.apps = list
                    AppIndex.shared.scannedAt = Date()
                    AppIndex.shared.scanning = false
                }
            }
        }
    }

    nonisolated private static func scan() -> [AppRecord] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let roots = ["/Applications", "/Applications/Utilities", "/System/Applications", "/System/Applications/Utilities",
                     "/System/Library/CoreServices/Applications", "\(home)/Applications", "/System/Library/CoreServices/Finder.app/Contents/Applications"]
        var seen: Set<String> = []
        var out: [AppRecord] = []
        func add(_ path: String) {
            guard !seen.contains(path) else { return }
            seen.insert(path)
            let bundle = Bundle(path: path)
            let display = (FileManager.default.displayName(atPath: path) as NSString).deletingPathExtension
            let file = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
            out.append(AppRecord(name: display, fileName: file, path: path, bundleID: bundle?.bundleIdentifier))
        }
        for root in roots {
            guard let items = try? FileManager.default.contentsOfDirectory(atPath: root) else { continue }
            for item in items where item.hasSuffix(".app") { add("\(root)/\(item)") }
            for item in items where !item.hasSuffix(".app") && !item.hasPrefix(".") {
                let folder = "\(root)/\(item)"
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: folder, isDirectory: &isDirectory), isDirectory.boolValue,
                      let inner = try? FileManager.default.contentsOfDirectory(atPath: folder) else { continue }
                for app in inner where app.hasSuffix(".app") { add("\(folder)/\(app)") }
            }
        }
        add("/System/Library/CoreServices/Finder.app")
        return out
    }
}

// MARK: Menus

struct MenuRecord {
    let path: [String]
    let shortcut: String?
    let enabled: Bool
    let box: AXBox
    var title: String { path.last ?? "" }
}

enum MenuIndex {
    /// Every command in the menu bar of an app, three levels deep, without opening a menu.
    nonisolated static func collect(_ pid: pid_t) -> [MenuRecord] {
        let app = AX.app(pid)
        guard let bar = AX.element(app, kAXMenuBarAttribute) else { return [] }
        var out: [MenuRecord] = []
        for top in AX.elements(bar, kAXChildrenAttribute).dropFirst() {
            let title = AX.title(top) ?? ""
            for menu in AX.elements(top, kAXChildrenAttribute) { walk(menu, [title], depth: 0, into: &out) }
        }
        return out
    }

    nonisolated private static func walk(_ menu: AXUIElement, _ path: [String], depth: Int, into out: inout [MenuRecord]) {
        guard depth < 3, out.count < 1500 else { return }
        for item in AX.elements(menu, kAXChildrenAttribute) {
            guard let title = AX.title(item), !title.isEmpty else { continue }
            if let submenu = AX.elements(item, kAXChildrenAttribute).first {
                walk(submenu, path + [title], depth: depth + 1, into: &out)
            } else {
                out.append(MenuRecord(path: path + [title], shortcut: shortcut(item), enabled: AX.bool(item, kAXEnabledAttribute) ?? true, box: AXBox(item)))
            }
        }
    }

    nonisolated private static func shortcut(_ item: AXUIElement) -> String? {
        guard let key = AX.string(item, kAXMenuItemCmdCharAttribute), !key.isEmpty else { return nil }
        let modifiers = (AX.value(item, kAXMenuItemCmdModifiersAttribute) as? NSNumber)?.intValue ?? 0
        var glyphs = ""
        if modifiers & 4 != 0 { glyphs += "⌃" }
        if modifiers & 2 != 0 { glyphs += "⌥" }
        if modifiers & 1 != 0 { glyphs += "⇧" }
        if modifiers & 8 == 0 { glyphs += "⌘" }
        return glyphs + key.uppercased()
    }
}

// MARK: Files

/// Spotlight search in the home folder, newest use first.
@MainActor
final class FileSearch {
    private var query: NSMetadataQuery?
    private var observers: [NSObjectProtocol] = []
    var onResults: (([URL]) -> Void)?

    func search(_ text: String) {
        stop()
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else {
            onResults?([])
            return
        }
        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryUserHomeScope]
        query.predicate = NSPredicate(format: "%K LIKE[cd] %@", NSMetadataItemFSNameKey, "*\(trimmed)*")
        query.sortDescriptors = [NSSortDescriptor(key: "kMDItemLastUsedDate", ascending: false)]
        let center = NotificationCenter.default
        for name in [Notification.Name.NSMetadataQueryDidFinishGathering, .NSMetadataQueryGatheringProgress, .NSMetadataQueryDidUpdate] {
            observers.append(center.addObserver(forName: name, object: query, queue: .main) { _ in
                MainActor.assumeIsolated { Suite.shared.commands.bar.files.deliver() }
            })
        }
        self.query = query
        query.start()
    }

    fileprivate func deliver() {
        guard let query else { return }
        query.disableUpdates()
        var urls: [URL] = []
        for index in 0..<min(query.resultCount, 24) {
            if let item = query.result(at: index) as? NSMetadataItem, let path = item.value(forAttribute: NSMetadataItemPathKey) as? String {
                if path.contains("/Library/") || path.contains("/.") { continue }
                urls.append(URL(fileURLWithPath: path))
            }
        }
        query.enableUpdates()
        onResults?(Array(urls.prefix(10)))
    }

    func stop() {
        query?.stop()
        query = nil
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers = []
    }
}

// MARK: Calculator

enum Calculator {
    /// Evaluates arithmetic with + − × ÷ ^ % !, brackets, functions and constants; nil unless it is clearly a formula.
    static func evaluate(_ input: String) -> Double? {
        var text = input.lowercased()
            .replacingOccurrences(of: "×", with: "*").replacingOccurrences(of: "÷", with: "/")
            .replacingOccurrences(of: "−", with: "-").replacingOccurrences(of: "π", with: "pi")
        text = text.replacingOccurrences(of: #"(\d),(\d)"#, with: "$1.$2", options: .regularExpression)
        text = text.replacingOccurrences(of: #"([\d.]+)\s*%\s*(of|от)\s*"#, with: "$1/100*", options: .regularExpression)
        text = text.replacingOccurrences(of: " ", with: "")
        if text.hasSuffix("=") { text.removeLast() }
        guard !text.isEmpty, text.range(of: #"[+\-*/^%!()]|sqrt|sin|cos|tan|log|ln|pi|abs|exp|round|floor|ceil"#, options: .regularExpression) != nil,
              text.range(of: #"^[\d.]+$"#, options: .regularExpression) == nil else { return nil }
        var parser = ExpressionParser(Array(text))
        guard let value = parser.expression(), parser.done, value.isFinite else { return nil }
        return value
    }

    @MainActor static func format(_ value: Double) -> String {
        if abs(value) >= 1e15 || (abs(value) < 1e-6 && value != 0) { return String(format: "%.6g", value) }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 10
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = " "
        formatter.decimalSeparator = Suite.shared.language == .en ? "." : ","
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

private struct ExpressionParser {
    let chars: [Character]
    var index = 0

    init(_ chars: [Character]) { self.chars = chars }

    var done: Bool { index >= chars.count }
    private var peek: Character? { index < chars.count ? chars[index] : nil }

    mutating func expression() -> Double? {
        guard var lhs = term() else { return nil }
        while let op = peek, op == "+" || op == "-" {
            index += 1
            let start = index
            guard var rhs = term() else { return nil }
            if index > start, chars[index - 1] == "%", !chars[start..<index].contains(where: { "*/^(".contains($0) }) { rhs *= lhs }
            lhs = op == "+" ? lhs + rhs : lhs - rhs
        }
        return lhs
    }

    private mutating func term() -> Double? {
        guard var lhs = factor() else { return nil }
        while let op = peek, op == "*" || op == "/" {
            index += 1
            guard let rhs = factor() else { return nil }
            lhs = op == "*" ? lhs * rhs : lhs / rhs
        }
        return lhs
    }

    private mutating func factor() -> Double? {
        if peek == "-" {
            index += 1
            return factor().map { -$0 }
        }
        if peek == "+" {
            index += 1
            return factor()
        }
        guard let base = postfix() else { return nil }
        if peek == "^" {
            index += 1
            guard let exponent = factor() else { return nil }
            return pow(base, exponent)
        }
        return base
    }

    private mutating func postfix() -> Double? {
        guard var value = primary() else { return nil }
        while let next = peek {
            if next == "%" {
                value /= 100
                index += 1
            } else if next == "!" {
                guard value >= 0, value <= 170, value == value.rounded() else { return nil }
                value = (1...max(Int(value), 1)).reduce(1.0) { $0 * Double($1) }
                index += 1
            } else {
                break
            }
        }
        return value
    }

    private mutating func primary() -> Double? {
        guard let first = peek else { return nil }
        if first == "(" {
            index += 1
            guard let value = expression(), peek == ")" else { return nil }
            index += 1
            return value
        }
        if first.isNumber || first == "." {
            var text = ""
            while let next = peek, next.isNumber || next == "." {
                text.append(next)
                index += 1
            }
            if peek == "e", index + 1 < chars.count, chars[index + 1].isNumber || chars[index + 1] == "-" {
                text.append("e")
                index += 1
                if peek == "-" {
                    text.append("-")
                    index += 1
                }
                while let next = peek, next.isNumber {
                    text.append(next)
                    index += 1
                }
            }
            return Double(text)
        }
        if first.isLetter {
            var name = ""
            while let next = peek, next.isLetter || next.isNumber {
                name.append(next)
                index += 1
            }
            switch name {
            case "pi": return Double.pi
            case "e": return M_E
            default: break
            }
            guard peek == "(" else { return nil }
            index += 1
            guard let argument = expression(), peek == ")" else { return nil }
            index += 1
            switch name {
            case "sqrt": return sqrt(argument)
            case "cbrt": return cbrt(argument)
            case "sin": return sin(argument)
            case "cos": return cos(argument)
            case "tan": return tan(argument)
            case "asin": return asin(argument)
            case "acos": return acos(argument)
            case "atan": return atan(argument)
            case "ln": return log(argument)
            case "log", "lg": return log10(argument)
            case "log2": return log2(argument)
            case "exp": return exp(argument)
            case "abs": return abs(argument)
            case "round": return argument.rounded()
            case "floor": return floor(argument)
            case "ceil": return ceil(argument)
            default: return nil
            }
        }
        return nil
    }
}

// MARK: Units and currency

enum Converter {
    struct Result {
        let input: String
        let output: String
        let value: Double
    }

    private static let pattern = #"^\s*(-?[\d.,]+)\s*([^\d\s][^\s]*?)\s+(?:in|to|в|во|на|->|→|=)\s+([^\s]+)\s*$"#

    private static let units: [String: Dimension] = {
        var map: [String: Dimension] = [:]
        func add(_ unit: Dimension, _ names: String...) { for name in names { map[name] = unit } }
        add(UnitLength.meters, "m", "м", "meter", "meters", "метр", "метра", "метров")
        add(UnitLength.kilometers, "km", "км", "kilometer", "kilometers", "километр", "километров")
        add(UnitLength.centimeters, "cm", "см", "сантиметр", "сантиметров")
        add(UnitLength.millimeters, "mm", "мм", "миллиметр", "миллиметров")
        add(UnitLength.miles, "mi", "mile", "miles", "миля", "мили", "миль")
        add(UnitLength.feet, "ft", "foot", "feet", "фут", "фута", "футов")
        add(UnitLength.inches, "inch", "inches", "дюйм", "дюйма", "дюймов", "\"")
        add(UnitLength.yards, "yd", "yard", "yards", "ярд", "ярдов")
        add(UnitLength.nauticalMiles, "nmi", "морская")
        add(UnitMass.kilograms, "kg", "кг", "kilo", "kilos", "килограмм", "килограммов")
        add(UnitMass.grams, "g", "г", "gram", "grams", "грамм", "граммов")
        add(UnitMass.milligrams, "mg", "мг")
        add(UnitMass.pounds, "lb", "lbs", "pound", "pounds", "фунт", "фунта", "фунтов")
        add(UnitMass.ounces, "oz", "ounce", "ounces", "унция", "унций")
        add(UnitMass.metricTons, "t", "т", "ton", "tons", "тонна", "тонн")
        add(UnitTemperature.celsius, "c", "°c", "с", "°с", "celsius", "цельсий", "цельсия")
        add(UnitTemperature.fahrenheit, "f", "°f", "ф", "fahrenheit", "фаренгейт", "фаренгейта")
        add(UnitTemperature.kelvin, "k", "kelvin", "кельвин", "кельвина")
        add(UnitVolume.liters, "l", "л", "liter", "liters", "литр", "литра", "литров")
        add(UnitVolume.milliliters, "ml", "мл")
        add(UnitVolume.gallons, "gal", "gallon", "gallons", "галлон", "галлонов")
        add(UnitVolume.cups, "cup", "cups", "чашка", "чашки")
        add(UnitVolume.fluidOunces, "floz")
        add(UnitSpeed.kilometersPerHour, "kmh", "km/h", "кмч", "км/ч")
        add(UnitSpeed.milesPerHour, "mph")
        add(UnitSpeed.metersPerSecond, "m/s", "мс", "м/с")
        add(UnitSpeed.knots, "kn", "knot", "knots", "узел", "узлов")
        add(UnitDuration.seconds, "s", "sec", "secs", "second", "seconds", "с.", "сек", "секунда", "секунд")
        add(UnitDuration.minutes, "min", "mins", "minute", "minutes", "мин", "минута", "минут", "минуты")
        add(UnitDuration.hours, "h", "hr", "hrs", "hour", "hours", "ч", "час", "часа", "часов")
        add(UnitInformationStorage.bytes, "b", "byte", "bytes", "байт", "байта")
        add(UnitInformationStorage.kilobytes, "kb", "кб")
        add(UnitInformationStorage.megabytes, "mb", "мб")
        add(UnitInformationStorage.gigabytes, "gb", "гб")
        add(UnitInformationStorage.terabytes, "tb", "тб")
        add(UnitInformationStorage.kibibytes, "kib")
        add(UnitInformationStorage.mebibytes, "mib")
        add(UnitInformationStorage.gibibytes, "gib")
        add(UnitArea.squareMeters, "m2", "м2", "m²", "м²")
        add(UnitArea.squareKilometers, "km2", "км2", "km²", "км²")
        add(UnitArea.hectares, "ha", "га", "гектар", "гектаров")
        add(UnitArea.acres, "acre", "acres", "акр", "акров")
        add(UnitArea.squareFeet, "ft2", "ft²", "sqft")
        add(UnitEnergy.kilocalories, "kcal", "ккал")
        add(UnitEnergy.kilojoules, "kj", "кдж")
        add(UnitEnergy.kilowattHours, "kwh", "квтч", "квт·ч")
        add(UnitPressure.bars, "bar", "бар")
        add(UnitPressure.poundsForcePerSquareInch, "psi")
        add(UnitPressure.millimetersOfMercury, "mmhg", "ммртст")
        return map
    }()

    static let currencies: [String: String] = [
        "usd": "USD", "$": "USD", "доллар": "USD", "доллара": "USD", "долларов": "USD", "долларах": "USD", "бакс": "USD", "баксов": "USD",
        "eur": "EUR", "€": "EUR", "евро": "EUR",
        "rub": "RUB", "₽": "RUB", "руб": "RUB", "рубль": "RUB", "рубля": "RUB", "рублей": "RUB", "рублях": "RUB", "р": "RUB",
        "uah": "UAH", "₴": "UAH", "грн": "UAH", "гривна": "UAH", "гривен": "UAH", "гривнах": "UAH",
        "gbp": "GBP", "£": "GBP", "jpy": "JPY", "¥": "JPY", "иена": "JPY", "иен": "JPY", "cny": "CNY", "юань": "CNY", "юаней": "CNY",
        "chf": "CHF", "pln": "PLN", "злотый": "PLN", "злотых": "PLN", "kzt": "KZT", "тенге": "KZT", "try": "TRY", "лира": "TRY", "лир": "TRY",
        "byn": "BYN", "cad": "CAD", "aud": "AUD", "sek": "SEK", "nok": "NOK", "czk": "CZK", "gel": "GEL", "лари": "GEL", "amd": "AMD",
        "aed": "AED", "дирхам": "AED", "inr": "INR", "krw": "KRW", "btc": "BTC"
    ]

    @MainActor static func convert(_ input: String) -> Result? {
        guard let match = input.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else { return nil }
        let text = String(input[match])
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let found = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let numberRange = Range(found.range(at: 1), in: text), let fromRange = Range(found.range(at: 2), in: text),
              let toRange = Range(found.range(at: 3), in: text) else { return nil }
        let number = Double(text[numberRange].replacingOccurrences(of: ",", with: ".")) ?? .nan
        guard number.isFinite else { return nil }
        let from = text[fromRange].lowercased()
        let to = text[toRange].lowercased()
        if let a = currencies[from], let b = currencies[to] {
            guard let value = CurrencyRates.shared.convert(number, from: a, to: b) else {
                CurrencyRates.shared.refresh()
                return Result(input: "\(Calculator.format(number)) \(a)", output: "… \(b)", value: .nan)
            }
            return Result(input: "\(Calculator.format(number)) \(a)", output: "\(Calculator.format((value * 100).rounded() / 100)) \(b)", value: value)
        }
        guard let a = units[from], let b = units[to], type(of: a) == type(of: b) else { return nil }
        let value = Measurement(value: number, unit: a).converted(to: b).value
        let formatter = MeasurementFormatter()
        formatter.unitOptions = .providedUnit
        formatter.numberFormatter.maximumFractionDigits = 4
        formatter.locale = Locale(identifier: Suite.shared.language == .en ? "en_US" : "ru_RU")
        return Result(input: formatter.string(from: Measurement(value: number, unit: a)),
                      output: formatter.string(from: Measurement(value: value, unit: b)), value: value)
    }
}

/// Daily exchange rates from open.er-api.com, kept between launches.
@MainActor
final class CurrencyRates {
    static let shared = CurrencyRates()
    private var rates: [String: Double] = [:]
    private var fetchedAt = Date.distantPast
    private var loading = false

    init() {
        let defaults = UserDefaults.standard
        rates = defaults.dictionary(forKey: "suite.rates") as? [String: Double] ?? [:]
        fetchedAt = defaults.object(forKey: "suite.ratesAt") as? Date ?? .distantPast
    }

    /// Installs rates for a test without writing them to the user's defaults.
    func testingRates(_ rates: [String: Double]) {
        self.rates = rates
        fetchedAt = Date()
        loading = false
    }

    func convert(_ value: Double, from: String, to: String) -> Double? {
        if Date().timeIntervalSince(fetchedAt) > 43_200 { refresh() }
        guard let a = rates[from], let b = rates[to], a > 0 else { return nil }
        return value / a * b
    }

    func refresh() {
        guard !loading, let url = URL(string: "https://open.er-api.com/v6/latest/USD") else { return }
        loading = true
        URLSession.shared.dataTask(with: url) { data, _, _ in
            let parsed = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            let fresh = (parsed?["rates"] as? [String: Any])?.compactMapValues { ($0 as? NSNumber)?.doubleValue } ?? [:]
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    let rates = CurrencyRates.shared
                    rates.loading = false
                    guard !fresh.isEmpty else { return }
                    rates.rates = fresh
                    rates.fetchedAt = Date()
                    UserDefaults.standard.set(fresh, forKey: "suite.rates")
                    UserDefaults.standard.set(rates.fetchedAt, forKey: "suite.ratesAt")
                    Suite.shared.commands.bar.ratesArrived()
                }
            }
        }.resume()
    }
}

// MARK: Emoji

enum EmojiIndex {
    nonisolated(unsafe) private static var cache: [(emoji: String, name: String)]?

    static var all: [(emoji: String, name: String)] {
        if let cache { return cache }
        var list: [(String, String)] = []
        let ranges: [ClosedRange<UInt32>] = [0x1F300...0x1F5FF, 0x1F600...0x1F64F, 0x1F680...0x1F6FF, 0x1F900...0x1F9FF,
                                             0x1FA70...0x1FAFF, 0x2600...0x26FF, 0x2700...0x27BF]
        for range in ranges {
            for value in range {
                guard let scalar = Unicode.Scalar(value), scalar.properties.isEmojiPresentation,
                      let name = scalar.properties.name else { continue }
                list.append((String(Character(scalar)), name.lowercased()))
            }
        }
        cache = list
        return list
    }

    static func search(_ query: String, limit: Int = 12) -> [(emoji: String, name: String)] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return Array(all.prefix(limit)) }
        let scored = all.compactMap { entry -> (String, String, Double)? in
            guard let score = Fuzzy.score(entry.name, q), score >= 60 else { return nil }
            return (entry.emoji, entry.name, score)
        }
        return scored.sorted { $0.2 > $1.2 }.prefix(limit).map { ($0.0, $0.1) }
    }
}
