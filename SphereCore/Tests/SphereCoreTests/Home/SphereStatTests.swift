import Testing
@testable import SphereCore

@Suite("SphereStat")
struct SphereStatTests {
    @Test func travelPrefersUpcomingTrip() {
        let trip = SphereStat.travel(upcomingTrip: ("Kyoto", 12), visitedCount: 5)
        #expect(trip.statLine == "Kyoto in 12 d")

        let visited = SphereStat.travel(upcomingTrip: nil, visitedCount: 5)
        #expect(visited.statLine == "5 countries visited")

        let empty = SphereStat.travel(upcomingTrip: nil, visitedCount: 0)
        #expect(empty.statLine == "No trips planned")
    }

    @Test func mindfulnessCombinesStreakAndMood() {
        #expect(SphereStat.mindfulness(streakDays: 5, todayMood: 4).statLine == "5-day streak · mood 4/5")
        #expect(SphereStat.mindfulness(streakDays: 3, todayMood: nil).statLine == "3-day streak")
        #expect(SphereStat.mindfulness(streakDays: 0, todayMood: nil).statLine == "Check in with yourself")
    }

    @Test func creativityAndHomeSummaries() {
        #expect(SphereStat.creativity(inProgressCount: 2, avgProgress: 45).statLine == "2 active · 45% avg")
        #expect(SphereStat.creativity(inProgressCount: 0, avgProgress: 0).statLine == "Capture an idea")

        #expect(SphereStat.home(openTasks: 3, thirstyPlants: 1).statLine == "3 tasks · 1 plant thirsty")
        #expect(SphereStat.home(openTasks: 1, thirstyPlants: 0).statLine == "1 task")
        #expect(SphereStat.home(openTasks: 0, thirstyPlants: 0).statLine == "All tidy")
    }
}

@Suite("UserProfile sphere ordering")
struct SphereOrderingTests {
    @Test func orderedActiveSpheresRespectsSavedOrderAndTrailsRest() {
        var profile = UserProfile(sphereOrder: ["finance", "goals", "health"])
        // Saved three come first in that order; the rest follow in enum order.
        let ordered = profile.orderedActiveSpheres
        #expect(Array(ordered.prefix(3)) == [.finance, .goals, .health])
        #expect(ordered.count == SphereType.allCases.count)
        #expect(ordered[3] == .learning) // first enum sphere not in the saved order

        // Disabled spheres drop out entirely.
        profile.activeSpheres = ["finance", "goals"]
        #expect(profile.orderedActiveSpheres == [.finance, .goals])
    }

    @Test func emptyOrderIsDefaultEnumOrder() {
        #expect(UserProfile().orderedActiveSpheres == SphereType.allCases)
    }
}
