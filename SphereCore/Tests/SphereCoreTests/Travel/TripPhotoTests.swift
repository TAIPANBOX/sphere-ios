import Foundation
import Testing
@testable import SphereCore

/// Records saves/deletes and hands back predictable filenames.
private final class FakePhotoStore: TripPhotoStoring, @unchecked Sendable {
    private(set) var saved: [Data] = []
    private(set) var deleted: [String] = []
    var failNext = false

    func save(_ data: Data) -> String? {
        if failNext { return nil }
        saved.append(data)
        return "photo-\(saved.count).jpg"
    }
    func fileURL(for filename: String) -> URL? { URL(string: "file:///tmp/\(filename)") }
    func delete(_ filename: String) { deleted.append(filename) }
}

@Suite("TravelStore photos")
@MainActor
struct TripPhotoTests {
    private func makeStore(_ photoStore: FakePhotoStore?) throws -> TravelStore {
        let database = try AppDatabase.inMemory()
        return TravelStore(database: database, photoStore: photoStore)
    }

    @Test func addPhotoSavesFileAndRow() async throws {
        let fake = FakePhotoStore()
        let store = try makeStore(fake)
        let photo = await store.addPhoto(planId: "trip1", data: Data([0x1, 0x2]), caption: "Beach")
        #expect(photo != nil)
        #expect(fake.saved.count == 1)
        #expect(store.photos(for: "trip1").count == 1)
        #expect(store.photos(for: "trip1").first?.caption == "Beach")
        #expect(store.photoURL(for: photo!)?.absoluteString == "file:///tmp/photo-1.jpg")
    }

    @Test func photosAreScopedToTrip() async throws {
        let store = try makeStore(FakePhotoStore())
        await store.addPhoto(planId: "a", data: Data([1]))
        await store.addPhoto(planId: "b", data: Data([2]))
        #expect(store.photos(for: "a").count == 1)
        #expect(store.photos(for: "b").count == 1)
    }

    @Test func removePhotoDeletesFileAndRow() async throws {
        let fake = FakePhotoStore()
        let store = try makeStore(fake)
        let photo = await store.addPhoto(planId: "a", data: Data([1]))!
        await store.removePhoto(id: photo.id)
        #expect(store.photos(for: "a").isEmpty)
        #expect(fake.deleted == ["photo-1.jpg"])
    }

    @Test func addReturnsNilWhenStoreFails() async throws {
        let fake = FakePhotoStore()
        fake.failNext = true
        let store = try makeStore(fake)
        let photo = await store.addPhoto(planId: "a", data: Data([1]))
        #expect(photo == nil)
        #expect(store.tripPhotos.isEmpty)
    }

    @Test func noPhotoStore() async throws {
        let store = try makeStore(nil)
        #expect(store.hasPhotoStore == false)
        #expect(await store.addPhoto(planId: "a", data: Data([1])) == nil)
    }

    @Test func photosSurviveReload() async throws {
        let database = try AppDatabase.inMemory()
        let store1 = TravelStore(database: database, photoStore: FakePhotoStore())
        await store1.addPhoto(planId: "a", data: Data([1]), caption: "Sunset")

        let store2 = TravelStore(database: database, photoStore: FakePhotoStore())
        try await store2.load()
        #expect(store2.photos(for: "a").first?.caption == "Sunset")
    }
}
