import Foundation
import Testing
@testable import SAVISUL

@Test func additionAndEqualsSign() {
    #expect(Calculator.evaluate("2+2") == 4)
    #expect(Calculator.evaluate("2 + 2 =") == 4)
    #expect(Calculator.evaluate("2 + 2 = ") == 4)
}

@Test func operatorSpellings() {
    #expect(Calculator.evaluate("8×3") == 24)
    #expect(Calculator.evaluate("8÷2") == 4)
    #expect(Calculator.evaluate("9−4") == 5)
    #expect(Calculator.evaluate("(2+3)*4") == 20)
    #expect(Calculator.evaluate("2^10") == 1024)
}

@Test func percentOfAndPercentAdded() {
    #expect(Calculator.evaluate("20% of 50") == 10)
    #expect(Calculator.evaluate("20% от 80") == 16)
    #expect(Calculator.evaluate("100+10%") == 110)
    #expect(Calculator.evaluate("50%") == 0.5)
}

@Test func functionsAndConstants() {
    #expect(Calculator.evaluate("sqrt(9)") == 3)
    #expect(Calculator.evaluate("abs(-4)") == 4)
    #expect(Calculator.evaluate("5!") == 120)
    #expect(Calculator.evaluate("1!") == 1)
    #expect(abs((Calculator.evaluate("pi*1") ?? 0) - Double.pi) < 0.0001)
    #expect(Calculator.evaluate("round(pi)") == 3)
    #expect(Calculator.evaluate("floor(3.9)") == 3)
    #expect(Calculator.evaluate("ceil(1.1)") == 2)
}

@Test func decimalCommaAndRejectsProse() {
    #expect(Calculator.evaluate("1,5+2,5") == 4)
    #expect(Calculator.evaluate("hello") == nil)
    #expect(Calculator.evaluate("") == nil)
    #expect(Calculator.evaluate("42") == nil)
    #expect(Calculator.evaluate("5!6") == nil)
    #expect(Calculator.evaluate("1/0") == nil)
    #expect(Calculator.evaluate("(-1)!") == nil)
}

@Test func factorialLimitAndNestedParens() {
    #expect(Calculator.evaluate("3!!") == 720)
    #expect(Calculator.evaluate("171!") == nil)
    #expect(Calculator.evaluate("((1+2)*3)-4") == 5)
    #expect(Calculator.evaluate("(1+2") == nil)
}

@Test func fuzzyRanks() {
    #expect(Fuzzy.score("Safari", "safari") == 100)
    let prefix = Fuzzy.score("Safari", "saf")
    #expect(prefix != nil)
    #expect((prefix ?? 0) > 80)
    #expect(Fuzzy.score("Google Chrome", "chr") == 78)
    #expect(Fuzzy.score("Visual Studio Code", "vsc") == 72)
    #expect(Fuzzy.score("Notes", "ote") == 62)
    #expect(Fuzzy.score("Finder", "") == nil)
    #expect(Fuzzy.score("Finder", "zzz") == nil)
    let subsequence = Fuzzy.score("clipboard", "cbd")
    #expect(subsequence != nil)
    #expect((subsequence ?? 100) <= 40)
}

@Test func otherKeyboardLayout() {
    #expect(Fuzzy.otherLayout("ыфафкш") == "safari")
    #expect(Fuzzy.otherLayout("safari") == "ыфафкш")
    #expect(Fuzzy.otherLayout("123") == nil)
}

@Suite
@MainActor
struct CommandConversionTests {
    @Test func unitConversion() {
        Suite.shared.language = .en
        let kilometres = Converter.convert("10 km in mi")
        #expect(kilometres != nil)
        #expect(abs((kilometres?.value ?? 0) - 6.21371) < 0.01)
        #expect(abs((Converter.convert("2 м в см")?.value ?? 0) - 200) < 0.001)
        #expect(abs((Converter.convert("100 c to f")?.value ?? 0) - 212) < 0.01)
        #expect(Converter.convert("10 km in kg") == nil)
        #expect(Converter.convert("not a conversion") == nil)
    }

    @Test func currencyUsesInstalledRates() {
        Suite.shared.language = .en
        CurrencyRates.shared.testingRates(["USD": 1, "EUR": 0.9, "RUB": 90])
        #expect(abs((CurrencyRates.shared.convert(10, from: "USD", to: "EUR") ?? 0) - 9) < 0.001)
        #expect(abs((Converter.convert("10 usd in eur")?.value ?? 0) - 9) < 0.001)
        #expect(CurrencyRates.shared.convert(1, from: "USD", to: "NO_SUCH") == nil)
    }

    @Test func formatFollowsLanguage() {
        Suite.shared.language = .en
        let english = Calculator.format(1.5)
        #expect(english.contains("."))
        Suite.shared.language = .ru
        #expect(Calculator.format(1.5).contains(","))
        Suite.shared.language = .en
    }
}
