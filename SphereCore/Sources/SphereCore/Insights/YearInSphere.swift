import Foundation

/// The year's cross-sphere totals, gathered by `RecapStore`.
public struct RecapStats: Sendable, Equatable {
    public var year: Int
    public var meditationMinutes: Int
    public var focusMinutes: Int
    public var workouts: Int
    public var countriesVisited: Int
    public var journalEntries: Int
    public var gratitudeNotes: Int
    public var creativeMinutes: Int
    public var hobbyMinutes: Int

    // NOTE: only metrics whose records carry a date are included, so every
    // number is genuinely for `year`. Books/goals have no completion date, so
    // they'd leak lifetime totals into a per-year recap and are omitted.
    public init(
        year: Int, meditationMinutes: Int = 0, focusMinutes: Int = 0, workouts: Int = 0,
        countriesVisited: Int = 0, journalEntries: Int = 0, gratitudeNotes: Int = 0,
        creativeMinutes: Int = 0, hobbyMinutes: Int = 0
    ) {
        self.year = year
        self.meditationMinutes = meditationMinutes
        self.focusMinutes = focusMinutes
        self.workouts = workouts
        self.countriesVisited = countriesVisited
        self.journalEntries = journalEntries
        self.gratitudeNotes = gratitudeNotes
        self.creativeMinutes = creativeMinutes
        self.hobbyMinutes = hobbyMinutes
    }
}

/// One shareable recap card in the "Year in Sphere" story.
public struct RecapCard: Sendable, Equatable, Identifiable {
    public let id: String
    public let emoji: String
    /// The big number / headline line.
    public let value: String
    /// The supporting caption under it.
    public let caption: String
    public let sphere: SphereType?

    public init(id: String, emoji: String, value: String, caption: String, sphere: SphereType? = nil) {
        self.id = id
        self.emoji = emoji
        self.value = value
        self.caption = caption
        self.sphere = sphere
    }
}

/// Pure builder for the free, shareable annual recap (Spotify-Wrapped-style,
/// generalised across every sphere). Skips empty metrics so a light year still
/// tells a clean story.
public enum YearInSphere {
    public static func cards(from stats: RecapStats) -> [RecapCard] {
        var cards: [RecapCard] = [
            RecapCard(
                id: "intro", emoji: "✨", value: "Your \(stats.year)",
                caption: "in Sphere — a year across every part of your life."
            )
        ]

        func add(_ id: String, _ emoji: String, _ n: Int, _ caption: String, _ sphere: SphereType?) {
            guard n > 0 else { return }
            cards.append(RecapCard(id: id, emoji: emoji, value: formatted(n), caption: caption, sphere: sphere))
        }

        add("meditation", "🧘", stats.meditationMinutes, "minutes of calm", .mindfulness)
        add("focus", "🎯", stats.focusMinutes, "minutes in deep focus", .mindfulness)
        add("workouts", "🏋️", stats.workouts, "workouts crushed", .health)
        add("countries", "🌍", stats.countriesVisited, "countries explored", .travel)
        add("journal", "📝", stats.journalEntries, "journal entries written", .mindfulness)
        add("gratitude", "🙏", stats.gratitudeNotes, "moments of gratitude", .mindfulness)
        add("creative", "🎨", stats.creativeMinutes, "minutes creating", .creativity)
        add("hobby", "🎸", stats.hobbyMinutes, "minutes on what you love", .hobbies)

        return cards
    }

    /// True when nothing but the intro card would show.
    public static func isEmpty(_ stats: RecapStats) -> Bool {
        cards(from: stats).count <= 1
    }

    /// One-line summary for the ShareLink text.
    public static func summaryLine(_ stats: RecapStats) -> String {
        var parts: [String] = []
        if stats.meditationMinutes > 0 { parts.append("\(formatted(stats.meditationMinutes)) mindful minutes") }
        if stats.workouts > 0 { parts.append("\(stats.workouts) workouts") }
        if stats.countriesVisited > 0 { parts.append("\(stats.countriesVisited) countries") }
        if stats.journalEntries > 0 { parts.append("\(stats.journalEntries) journal entries") }
        let body = parts.isEmpty ? "a year of small steps" : parts.prefix(4).joined(separator: ", ")
        return "My \(stats.year) in Sphere: \(body)."
    }

    static func formatted(_ n: Int) -> String {
        let digits = String(n)
        guard digits.count > 3 else { return digits }
        var out = ""
        for (i, c) in digits.reversed().enumerated() {
            if i > 0, i % 3 == 0 { out.append(",") }
            out.append(c)
        }
        return String(out.reversed())
    }
}
