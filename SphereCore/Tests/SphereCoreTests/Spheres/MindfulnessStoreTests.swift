import Foundation
import Testing
@testable import SphereCore

@Suite("MindfulnessStore")
@MainActor
struct MindfulnessStoreTests {
    private func makeStore(engram: EngramStore? = nil) throws -> (MindfulnessStore, AppDatabase) {
        let database = try AppDatabase.inMemory()
        return (MindfulnessStore(database: database, engram: engram), database)
    }

    private func session(
        _ id: String, minutes: Int = 10, daysAgo: Int = 0, from now: Date = Date()
    ) -> MeditationSession {
        MeditationSession(
            id: id, durationMinutes: minutes,
            date: now.addingTimeInterval(Double(-daysAgo) * 86_400)
        )
    }

    // MARK: - Meditation

    @Test func streakRequiresTodayAndConsecutiveDays() async throws {
        let now = Date()
        let (store, _) = try makeStore()
        #expect(store.currentStreak(asOf: now) == 0)

        try await store.add(session("m1", daysAgo: 0, from: now))
        try await store.add(session("m2", daysAgo: 1, from: now))
        try await store.add(session("m3", daysAgo: 3, from: now))
        #expect(store.currentStreak(asOf: now) == 2)
        #expect(store.hasMeditated(on: now))

        // Without a session today the streak is zero (Dart semantics).
        let (gapStore, _) = try makeStore()
        try await gapStore.add(session("m1", daysAgo: 1, from: now))
        #expect(gapStore.currentStreak(asOf: now) == 0)
    }

    @Test func sessionsPersistNewestFirstWithTotals() async throws {
        let engram = try EngramStore.inMemory()
        let (store, database) = try makeStore(engram: engram)
        try await store.add(session("m1", minutes: 10, daysAgo: 1))
        try await store.add(MeditationSession(
            id: "m2", type: .bodyScan, durationMinutes: 20, date: Date()
        ))

        #expect(store.totalMinutes == 30)

        let reloaded = MindfulnessStore(database: database)
        try await reloaded.load()
        #expect(reloaded.sessions.map(\.id) == ["m2", "m1"])

        var count = 0
        for _ in 0..<50 where count < 2 {
            count = try await engram.count(agentId: "mindfulness")
            if count < 2 { try await Task.sleep(for: .milliseconds(20)) }
        }
        let memories = try await engram.recall("meditated", agentId: "mindfulness")
        #expect(memories.contains { $0.content == "Meditated 20 min (bodyScan)" })
    }

    // MARK: - Mood & stress

    @Test func moodIsDayKeyedAndOverwrites() async throws {
        let now = Date()
        let (store, database) = try makeStore()
        #expect(store.todaysMood(asOf: now) == nil)

        try await store.setMood(3, on: now)
        try await store.setMood(5, on: now)
        try await store.setMood(2, on: now.addingTimeInterval(-86_400))

        #expect(store.todaysMood(asOf: now) == 5)
        #expect(store.last7Moods(asOf: now).suffix(2) == [2, 5])

        let reloaded = MindfulnessStore(database: database)
        try await reloaded.load()
        #expect(reloaded.todaysMood(asOf: now) == 5)
    }

    @Test func stressUpsertsAndFillsLast7WithZeros() async throws {
        let now = Date()
        let (store, _) = try makeStore()
        try await store.setStress(7, on: now)
        try await store.setStress(4, on: now.addingTimeInterval(-2 * 86_400))

        #expect(store.todayStress(asOf: now) == 7)
        let last7 = store.last7Stress(asOf: now)
        #expect(last7.count == 7)
        #expect(last7[6] == 7)
        #expect(last7[4] == 4)
        #expect(last7[0] == 0)
    }

    // MARK: - Journal

    @Test func journalRecentOrderAndEngramPreviewTruncation() async throws {
        let engram = try EngramStore.inMemory()
        let (store, _) = try makeStore(engram: engram)
        let longText = String(repeating: "а", count: 250)
        try await store.addJournal(longText)
        try await store.addJournal("Second entry", on: Date().addingTimeInterval(60))

        #expect(store.recentJournal.first?.text == "Second entry")

        var count = 0
        for _ in 0..<50 where count < 2 {
            count = try await engram.count(agentId: "mindfulness")
            if count < 2 { try await Task.sleep(for: .milliseconds(20)) }
        }
        let memories = try await engram.recall("journal", agentId: "mindfulness")
        let preview = memories.first { $0.content.hasPrefix("Journal entry: аа") }
        #expect(preview?.content.hasSuffix("…") == true)
        #expect((preview?.content.count ?? 0) < 220)
    }

    // MARK: - Agent tools

    @Test func logMeditationToolMatchesDart() async throws {
        let (store, _) = try makeStore()
        let registry = SphereToolRegistry(tools: store.tools)

        let call = LLMToolCall(
            id: "t1", name: "log_meditation", input: ["minutes": 15, "type": "bodyScan"]
        )
        let result = await registry.execute(call)
        #expect(!result.isError)
        #expect(store.sessions.first?.type == .bodyScan)
        #expect(registry.confirmation(for: call) == "Logged 15-min meditation")

        // Unknown type degrades to breathing; missing minutes fails.
        _ = await registry.execute(LLMToolCall(
            id: "t2", name: "log_meditation", input: ["minutes": 5, "type": "zen"]
        ))
        #expect(store.sessions.first?.type == .breathing)
        let bad = await registry.execute(
            LLMToolCall(id: "t3", name: "log_meditation", input: .object([:]))
        )
        #expect(bad.isError)
    }

    @Test func logMoodAndJournalToolsMatchDart() async throws {
        let (store, _) = try makeStore()
        let registry = SphereToolRegistry(tools: store.tools)

        let moodCall = LLMToolCall(id: "t1", name: "log_mood", input: ["score": 4])
        _ = await registry.execute(moodCall)
        #expect(store.todaysMood() == 4)
        #expect(registry.confirmation(for: moodCall) == "Logged today's mood: 4/5")

        let outOfRange = await registry.execute(
            LLMToolCall(id: "t2", name: "log_mood", input: ["score": 9])
        )
        #expect(outOfRange.isError)

        let journalCall = LLMToolCall(
            id: "t3", name: "add_journal_entry", input: ["text": "Grateful for the sea"]
        )
        _ = await registry.execute(journalCall)
        #expect(store.journal.first?.text == "Grateful for the sea")
        #expect(registry.confirmation(for: journalCall) == "Saved journal entry")
    }

    @Test func mindfulnessSummaryToolIsSilentAndComplete() async throws {
        let (store, _) = try makeStore()
        try await store.add(session("m1", minutes: 12))
        try await store.setMood(4)
        try await store.setStress(6)
        try await store.addJournal(String(repeating: "b", count: 200))
        let registry = SphereToolRegistry(tools: store.tools)

        let call = LLMToolCall(id: "t1", name: "get_mindfulness_summary", input: .object([:]))
        let result = await registry.execute(call)
        let json = JSONValue.decoded(from: result.content)

        #expect(json?["meditationStreakDays"]?.intValue == 1)
        #expect(json?["totalMeditationMinutes"]?.intValue == 12)
        #expect(json?["todayMood"]?.intValue == 4)
        #expect(json?["todayStress"]?.intValue == 6)
        let text = json?["recentJournal"]?[0]?["text"]?.stringValue
        #expect(text?.hasSuffix("…") == true)
        #expect((text?.count ?? 0) == 161)
        #expect(registry.confirmation(for: call) == nil)
    }

    @Test func summaryOmitsMoodAndStressWhenUnset() async throws {
        let (store, _) = try makeStore()
        let registry = SphereToolRegistry(tools: store.tools)
        let result = await registry.execute(
            LLMToolCall(id: "t1", name: "get_mindfulness_summary", input: .object([:]))
        )
        let json = JSONValue.decoded(from: result.content)
        #expect(json?["todayMood"] == nil)
        #expect(json?["todayStress"] == nil)
    }

    @Test func toolsAreScopedToMindfulnessSphere() throws {
        let (store, _) = try makeStore()
        let registry = SphereToolRegistry(tools: store.tools)
        #expect(
            registry.toolsFor(.mindfulness).map(\.name).sorted() == [
                "add_journal_entry", "get_mindfulness_summary", "log_meditation", "log_mood",
            ]
        )
        #expect(registry.toolsFor(.travel).isEmpty)
    }
}
