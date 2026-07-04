import Foundation
import Observation

/// Assembles a searchable corpus from every sphere store and ranks it with
/// `GlobalSearch`, plus surfaces matching Engram memories. One place knows how
/// to turn each sphere's records into `SearchItem`s.
@MainActor
@Observable
public final class SearchStore {
    private let goals: GoalsStore
    private let health: HealthStore
    private let finance: FinanceStore
    private let learning: LearningStore
    private let career: CareerStore
    private let relationships: RelationshipsStore
    private let homeSphere: HomeSphereStore
    private let travel: TravelStore
    private let hobbies: HobbiesStore
    private let creativity: CreativityStore
    private let mindfulness: MindfulnessStore
    private let engram: EngramStore

    public init(
        goals: GoalsStore, health: HealthStore, finance: FinanceStore,
        learning: LearningStore, career: CareerStore, relationships: RelationshipsStore,
        homeSphere: HomeSphereStore, travel: TravelStore, hobbies: HobbiesStore,
        creativity: CreativityStore, mindfulness: MindfulnessStore, engram: EngramStore
    ) {
        self.goals = goals
        self.health = health
        self.finance = finance
        self.learning = learning
        self.career = career
        self.relationships = relationships
        self.homeSphere = homeSphere
        self.travel = travel
        self.hobbies = hobbies
        self.creativity = creativity
        self.mindfulness = mindfulness
        self.engram = engram
    }

    /// Ranked sphere-record matches for the query.
    public func results(for query: String, limit: Int = 60) -> [SearchItem] {
        GlobalSearch.rank(query: query, items: corpus(), limit: limit)
    }

    public func grouped(for query: String, limit: Int = 60) -> [(sphere: SphereType, items: [SearchItem])] {
        GlobalSearch.grouped(results(for: query, limit: limit))
    }

    /// Matching memories from Engram's cross-agent FTS recall.
    public func memories(for query: String, k: Int = 6) async -> [EngramMemory] {
        (try? await engram.crossAgentRecall(query, k: k)) ?? []
    }

    // MARK: - Corpus

    private func corpus() -> [SearchItem] {
        var items: [SearchItem] = []
        func add(_ sphere: SphereType, _ id: String, _ title: String, _ subtitle: String = "", _ keywords: String = "") {
            guard !title.isEmpty else { return }
            items.append(SearchItem(
                id: "\(sphere.rawValue):\(id)", sphere: sphere,
                title: title, subtitle: subtitle, keywords: keywords
            ))
        }

        for g in goals.goals { add(.goals, g.id, g.title, g.why) }
        for h in goals.habits { add(.goals, h.id, h.name, "habit", h.identity) }

        for m in health.medications { add(.health, m.id, m.name, m.dosage) }
        for l in health.labResults { add(.health, l.id, l.name, "\(l.value) \(l.unit)") }

        for s in finance.subscriptions { add(.finance, s.id, s.name, "subscription") }

        for b in learning.books { add(.learning, b.id, b.title, b.author) }
        for c in learning.courses { add(.learning, c.id, c.name, c.provider) }

        for t in career.tasks { add(.career, t.id, t.title, t.project) }
        for i in career.interviews { add(.career, i.id, i.company, i.position) }
        for a in career.achievements { add(.career, a.id, a.title, a.impact) }
        for n in career.network { add(.career, n.id, n.name, "\(n.role) \(n.company)") }

        for c in relationships.contacts { add(.relationships, c.id, c.name, "contact") }

        for t in homeSphere.tasks { add(.home, t.id, t.title, "home task") }
        for p in homeSphere.plants { add(.home, p.id, p.name, "plant") }
        for i in homeSphere.inventory { add(.home, i.id, i.name, i.location, i.lentTo) }

        for p in travel.plans { add(.travel, p.id, p.destination, p.country) }
        for v in travel.visited { add(.travel, v.id, v.name, "visited") }

        for h in hobbies.hobbies { add(.hobbies, h.id, h.name, "hobby") }

        for p in creativity.projects { add(.creativity, p.id, p.title, p.description) }
        for i in creativity.ideas { add(.creativity, i.id, i.content, i.tag) }

        for j in mindfulness.journal { add(.mindfulness, j.id, j.text, "journal") }

        return items
    }
}
