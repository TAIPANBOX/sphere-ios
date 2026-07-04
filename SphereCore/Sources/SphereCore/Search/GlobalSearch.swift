import Foundation

/// One searchable record from any sphere (or an Engram memory), flattened to
/// title + subtitle + keywords so a single ranker can score them all.
public struct SearchItem: Sendable, Equatable, Identifiable {
    public let id: String
    public let sphere: SphereType
    public let title: String
    public let subtitle: String
    let titleLower: String
    let haystack: String

    public init(
        id: String, sphere: SphereType, title: String,
        subtitle: String = "", keywords: String = ""
    ) {
        self.id = id
        self.sphere = sphere
        self.title = title
        self.subtitle = subtitle
        self.titleLower = title.lowercased()
        self.haystack = "\(title) \(subtitle) \(keywords)".lowercased()
    }
}

/// Pure cross-sphere ranker. AND semantics: every query token must appear in an
/// item; title matches (and title prefixes) rank higher than body matches.
public enum GlobalSearch {
    public static func tokens(_ query: String) -> [String] {
        query.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    public static func rank(query: String, items: [SearchItem], limit: Int = 50) -> [SearchItem] {
        let terms = tokens(query)
        guard !terms.isEmpty else { return [] }

        let scored: [(item: SearchItem, score: Int)] = items.compactMap { item in
            var score = 0
            for term in terms {
                guard item.haystack.contains(term) else { return nil }
                if item.titleLower.contains(term) {
                    score += 3
                    if item.titleLower.hasPrefix(term) { score += 2 }
                } else {
                    score += 1
                }
            }
            return (item, score)
        }

        return scored
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.item.title < $1.item.title }
            .prefix(limit)
            .map(\.item)
    }

    /// Groups ranked items by sphere, preserving each sphere's best-hit order so
    /// the strongest sphere leads.
    public static func grouped(_ items: [SearchItem]) -> [(sphere: SphereType, items: [SearchItem])] {
        var order: [SphereType] = []
        var buckets: [SphereType: [SearchItem]] = [:]
        for item in items {
            if buckets[item.sphere] == nil { order.append(item.sphere) }
            buckets[item.sphere, default: []].append(item)
        }
        return order.map { ($0, buckets[$0] ?? []) }
    }
}
