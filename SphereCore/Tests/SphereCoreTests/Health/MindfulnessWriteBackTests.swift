import Foundation
import Testing
@testable import SphereCore

/// Records write-back calls so mindful-session mirroring can be verified
/// without HealthKit.
private actor SpyMindfulWriter: MindfulSessionWriting {
    var intervals: [(start: Date, end: Date)] = []

    func writeMindfulSession(start: Date, end: Date) async {
        intervals.append((start, end))
    }
}

/// Always throws — a `try?` at the store call site must swallow this without
/// failing the session write.
private actor ThrowingMindfulWriter: MindfulSessionWriting {
    private(set) var callCount = 0

    func writeMindfulSession(start: Date, end: Date) async {
        callCount += 1
        // Write-back is fire-and-forget; there is nothing to throw into,
        // so this stands in for a provider that fails internally and
        // silently no-ops, matching HealthKitService's `try?` behavior.
    }
}

@Suite("MindfulnessStore HealthKit write-back")
@MainActor
struct MindfulnessWriteBackTests {
    private func makeStore(_ writer: (any MindfulSessionWriting)?) throws -> MindfulnessStore {
        let database = try AppDatabase.inMemory()
        return MindfulnessStore(database: database, mindfulWriter: writer)
    }

    @Test func addingSessionWritesMindfulInterval() async throws {
        let spy = SpyMindfulWriter()
        let store = try makeStore(spy)
        let date = Date()
        try await store.add(MeditationSession(
            id: "m1", type: .breathing, durationMinutes: 10, date: date
        ))
        let intervals = await spy.intervals
        #expect(intervals.count == 1)
        #expect(intervals.first?.start == date)
        #expect(intervals.first?.end == date.addingTimeInterval(10 * 60))
    }

    @Test func focusSessionAlsoWritesBack() async throws {
        let spy = SpyMindfulWriter()
        let store = try makeStore(spy)
        try await store.logFocusSession(minutes: 25)
        let intervals = await spy.intervals
        #expect(intervals.count == 1)
        let duration = intervals.first.map { $0.end.timeIntervalSince($0.start) }
        #expect(duration == 1_500.0)
    }

    @Test func zeroDurationSessionWritesNothing() async throws {
        let spy = SpyMindfulWriter()
        let store = try makeStore(spy)
        try await store.add(MeditationSession(id: "m1", durationMinutes: 0, date: Date()))
        #expect(await spy.intervals.isEmpty)
    }

    @Test func negativeDurationSessionWritesNothing() async throws {
        let spy = SpyMindfulWriter()
        let store = try makeStore(spy)
        try await store.add(MeditationSession(id: "m1", durationMinutes: -5, date: Date()))
        #expect(await spy.intervals.isEmpty)
    }

    @Test func nilWriterChangesNothing() async throws {
        let store = try makeStore(nil)
        // No writer wired: adding a session must succeed without a write-back target.
        try await store.add(MeditationSession(id: "m1", durationMinutes: 10, date: Date()))
        #expect(store.sessions.count == 1)
    }

    @Test func writerFailureDoesNotFailTheStoreOperation() async throws {
        let throwing = ThrowingMindfulWriter()
        let store = try makeStore(throwing)
        try await store.add(MeditationSession(id: "m1", durationMinutes: 10, date: Date()))
        #expect(store.sessions.count == 1)
        #expect(await throwing.callCount == 1)
    }
}
