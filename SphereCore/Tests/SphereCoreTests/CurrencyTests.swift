import Foundation
import Testing
@testable import SphereCore

@Suite("Currency")
struct CurrencyTests {
    @Test func symbolsAndLabels() {
        #expect(Currency.usd.symbol == "$")
        #expect(Currency.uah.symbol == "₴")
        #expect(Currency.eur.label == "EUR €")
        #expect(Currency.gbp.code == "GBP")
    }

    @Test func formatPlacesSymbolPerCurrency() {
        // Symbol-prefix currencies.
        #expect(Currency.usd.format(1240) == "$1,240")
        #expect(Currency.eur.format(0) == "€0")
        // Rounds to whole units.
        #expect(Currency.usd.format(1240.7) == "$1,241")
        // Symbol-suffix currencies.
        #expect(Currency.uah.format(1240) == "1,240 ₴")
        #expect(Currency.pln.format(50) == "50 zł")
    }

    @Test func deviceDefaultFallsBackToUSD() {
        // Whatever the runner locale is, the result must be a known currency.
        #expect(Currency.allCases.contains(Currency.deviceDefault))
    }
}
