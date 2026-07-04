import Foundation

/// Display currency for the Finance sphere. A small curated list (not every
/// ISO code) covering the app's expected audience; extend as needed.
public enum Currency: String, CaseIterable, Codable, Sendable {
    case usd, eur, uah, gbp, pln, jpy, cad, aud, chf, inr

    public var code: String { rawValue.uppercased() }

    public var symbol: String {
        switch self {
        case .usd, .cad, .aud: "$"
        case .eur: "€"
        case .uah: "₴"
        case .gbp: "£"
        case .pln: "zł"
        case .jpy: "¥"
        case .chf: "CHF"
        case .inr: "₹"
        }
    }

    public var label: String {
        "\(code) \(symbol)"
    }

    /// Best-effort default from the device locale, falling back to USD.
    public static var deviceDefault: Currency {
        guard let code = Locale.current.currency?.identifier.lowercased(),
              let match = Currency(rawValue: code)
        else { return .usd }
        return match
    }

    /// Formats an amount with the currency symbol, no decimals
    /// (e.g. "$1,240", "1 240 ₴"). Symbol placement follows the currency.
    public func format(_ amount: Double) -> String {
        let rounded = Int(amount.rounded())
        let number = Self.groupedFormatter.string(from: NSNumber(value: rounded)) ?? "\(rounded)"
        switch self {
        case .uah, .pln:
            return "\(number) \(symbol)"
        default:
            return "\(symbol)\(number)"
        }
    }

    private static let groupedFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter
    }()
}
