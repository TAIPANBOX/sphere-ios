import Foundation

/// Tier-1 offline quick capture: turns short natural phrases (English or
/// Ukrainian) into sphere tool calls, so the most frequent logs need no AI at
/// all. One capture line may hold several facts ("coffee 4.50, mood 4, water
/// 2") — each comma/`and`/`і`-separated fragment is parsed independently.
/// Anything it can't parse falls through to the agent (tier 2) or a hint.
public enum CaptureRuleParser {
    public static func parse(_ text: String) -> [LLMToolCall] {
        fragments(of: text).enumerated().compactMap { index, fragment in
            match(fragment, index: index)
        }
    }

    private static func fragments(of text: String) -> [String] {
        // Convert decimal commas ("72,5") to dots first, so the comma can be
        // used as a fragment separator without splitting numbers apart.
        let normalized = text.lowercased()
            .replacingOccurrences(
                of: "([0-9]),([0-9])", with: "$1.$2", options: .regularExpression
            )
        var parts = [normalized]
        for separator in [",", ";", "\n", " and ", " та ", " і ", " плюс ", " + "] {
            parts = parts.flatMap { $0.components(separatedBy: separator) }
        }
        return parts.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private static func match(_ fragment: String, index: Int) -> LLMToolCall? {
        let number = firstNumber(in: fragment)
        func id(_ tag: String) -> String { "cap_\(index)_\(tag)" }

        if contains(fragment, ["water", "glass", "вод", "склянк"]) {
            let count = min(max(Int(number ?? 1), 1), 12)
            return LLMToolCall(
                id: id("water"), name: "log_water_glass",
                input: .object(["count": .number(Double(count))])
            )
        }
        if contains(fragment, ["weight", "kg", "кг", "ваг"]), let kg = number {
            return LLMToolCall(
                id: id("weight"), name: "log_weight", input: .object(["kg": .number(kg)])
            )
        }
        if contains(fragment, ["mood", "настр"]), let value = number {
            let score = min(max(Int(value), 1), 5)
            return LLMToolCall(
                id: id("mood"), name: "log_mood", input: .object(["score": .number(Double(score))])
            )
        }
        if contains(fragment, ["meditat", "медит"]), let value = number {
            let minutes = min(max(Int(value), 1), 240)
            return LLMToolCall(
                id: id("med"), name: "log_meditation",
                input: .object(["minutes": .number(Double(minutes))])
            )
        }
        if contains(fragment, ["energy", "енерг"]), let value = number {
            let level = min(max(Int(value), 1), 5)
            return LLMToolCall(
                id: id("energy"), name: "log_energy",
                input: .object(["level": .number(Double(level))])
            )
        }
        if contains(fragment, ["meal", "їж", "харч"]), let value = number {
            let quality = min(max(Int(value), 1), 5)
            return LLMToolCall(
                id: id("meal"), name: "log_meal",
                input: .object(["quality": .number(Double(quality))])
            )
        }
        if contains(fragment, spendVerbs), let amount = number, amount > 0 {
            return LLMToolCall(
                id: id("spend"), name: "add_transaction",
                input: .object([
                    "title": .string(spendTitle(fragment)),
                    "amount": .number(amount),
                    "type": .string("expense"),
                    "category": .string(spendCategory(fragment)),
                ])
            )
        }
        return nil
    }

    // MARK: - Helpers

    private static func contains(_ text: String, _ needles: [String]) -> Bool {
        needles.contains { text.contains($0) }
    }

    /// First integer/decimal in the fragment (accepts `72,5` and `72.5`).
    private static func firstNumber(in text: String) -> Double? {
        guard let range = text.range(of: "[0-9]+([.,][0-9]+)?", options: .regularExpression)
        else { return nil }
        return Double(text[range].replacingOccurrences(of: ",", with: "."))
    }

    private static let spendVerbs = [
        "spent", "paid", "bought", "spend", "cost",
        "витратив", "витратила", "витрат", "заплатив", "заплатила", "заплат",
        "купив", "купила",
    ]
    private static let fillers = ["on", "for", "the", "a", "на", "за", "у", "в"]

    private static func spendTitle(_ fragment: String) -> String {
        let words = fragment.split(separator: " ").map(String.init)
        let kept = words.filter { word in
            Double(word.replacingOccurrences(of: ",", with: ".")) == nil
                && !spendVerbs.contains(where: { word.hasPrefix($0) })
                && !fillers.contains(word)
        }
        let title = kept.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return title.isEmpty ? "Expense" : title.capitalizedFirstLetter
    }

    private static func spendCategory(_ fragment: String) -> String {
        if contains(fragment, ["coffee", "lunch", "dinner", "breakfast", "food", "grocer",
                               "кава", "обід", "вечер", "їж", "продукт"]) { return "food" }
        if contains(fragment, ["taxi", "uber", "bus", "train", "fuel", "gas",
                               "таксі", "автобус", "потяг", "паливо"]) { return "transport" }
        return "other"
    }
}

extension String {
    fileprivate var capitalizedFirstLetter: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}
