import Foundation

/// A quick-log action sent from the watch to the phone over WCSession. The
/// phone applies it to the matching store and pushes a fresh
/// ``WidgetSnapshot`` back. Encoded as a plain dictionary so it rides
/// `sendMessage` / `transferUserInfo` without a custom coder.
public enum WatchCommand: Equatable, Sendable {
    case logWater
    /// 1–5
    case logMood(Int)
    case logMeditation(minutes: Int)

    static let key = "cmd"

    public func encode() -> [String: Any] {
        switch self {
        case .logWater:
            return [Self.key: "water"]
        case .logMood(let score):
            return [Self.key: "mood", "value": score]
        case .logMeditation(let minutes):
            return [Self.key: "meditation", "minutes": minutes]
        }
    }

    public static func decode(_ dictionary: [String: Any]) -> WatchCommand? {
        switch dictionary[key] as? String {
        case "water":
            return .logWater
        case "mood":
            guard let score = dictionary["value"] as? Int else { return nil }
            return .logMood(score)
        case "meditation":
            guard let minutes = dictionary["minutes"] as? Int else { return nil }
            return .logMeditation(minutes: minutes)
        default:
            return nil
        }
    }
}
