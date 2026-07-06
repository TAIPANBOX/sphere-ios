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
    /// Check off a shopping item by id.
    case checkShopping(id: String)
    /// Ask the agent a question; the answer comes back on the next snapshot.
    /// Superseded by `.capture` but kept for backward compat with an old watch
    /// build that hasn't updated yet.
    case askAgent(query: String)
    /// Log-or-ask: the phone decides whether the text can be captured as a
    /// fact across the spheres, or should be answered as a question. The
    /// result (chips or reply) comes back on the next snapshot.
    case capture(text: String)

    static let key = "cmd"

    public func encode() -> [String: Any] {
        switch self {
        case .logWater:
            return [Self.key: "water"]
        case .logMood(let score):
            return [Self.key: "mood", "value": score]
        case .logMeditation(let minutes):
            return [Self.key: "meditation", "minutes": minutes]
        case .checkShopping(let id):
            return [Self.key: "shopping", "id": id]
        case .askAgent(let query):
            return [Self.key: "ask", "query": query]
        case .capture(let text):
            return [Self.key: "capture", "text": text]
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
        case "shopping":
            guard let id = dictionary["id"] as? String, !id.isEmpty else { return nil }
            return .checkShopping(id: id)
        case "ask":
            guard let query = dictionary["query"] as? String, !query.isEmpty else { return nil }
            return .askAgent(query: query)
        case "capture":
            guard let text = dictionary["text"] as? String, !text.isEmpty else { return nil }
            return .capture(text: text)
        default:
            return nil
        }
    }
}
