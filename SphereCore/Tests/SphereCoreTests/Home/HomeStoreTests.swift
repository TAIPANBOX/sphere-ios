import Foundation
import Testing
@testable import SphereCore

@Suite("HomeStore & Weather")
@MainActor
struct HomeStoreTests {
    private func makeHome(
        engine: StubEngine? = nil,
        weatherJSON: String? = nil
    ) throws -> HomeStore {
        let database = try AppDatabase.inMemory()
        let agent = engine.map { engine in
            AgentService(
                keyStore: InMemoryAPIKeyStore([.openrouter: "key"]),
                engram: try! EngramStore.inMemory(),
                cache: InMemoryCache(),
                engineFactory: { _ in engine }
            )
        }
        let weatherService = weatherJSON.map { json in
            WeatherService(fetch: { _ in Data(json.utf8) })
        }
        return HomeStore(
            health: HealthStore(database: database),
            learning: LearningStore(database: database),
            career: CareerStore(database: database),
            finance: FinanceStore(database: database),
            goals: GoalsStore(database: database),
            agent: agent,
            weatherService: weatherService,
            location: weatherJSON != nil ? FixedLocation() : nil
        )
    }

    @Test func lifeScoreAggregatesDefaultsWhenEmpty() throws {
        let home = try makeHome()
        // 8 spheres of defaults: (0.75+0.5+0.85+0.5+0.75+0.5+0.5+0.5)/8 → 61%
        #expect(home.lifeScore == 61)
        #expect(home.scores.count == 8)
        #expect(home.bestSphere?.sphere == .career)
        #expect(home.focusItems.count >= 5)
    }

    @Test func briefStreamsIntoText() async throws {
        let engine = StubEngine(scripts: [[
            .textDelta("Ранок! "), .textDelta("Все добре."), .stop(.endTurn),
        ]])
        let home = try makeHome(engine: engine)

        await home.streamBrief()
        #expect(home.briefText == "Ранок! Все добре.")
        #expect(home.briefState == .done)
    }

    @Test func briefFailureProducesReadableState() async throws {
        let engine = StubEngine()
        engine.streamError = .backendUnavailable
        let home = try makeHome(engine: engine)

        await home.streamBrief()
        #expect(home.briefState == .failed("Offline — reconnect to refresh your brief."))
    }

    @Test func briefWithoutAgentStaysIdle() async throws {
        let home = try makeHome()
        await home.streamBrief()
        #expect(home.briefState == .idle)
    }

    @Test func weatherParsesOpenMeteoPayload() async throws {
        let json = """
        {
          "current": {"temperature_2m": 21.4, "weather_code": 3},
          "daily": {
            "time": ["2026-07-03", "2026-07-04", "2026-07-05", "2026-07-06"],
            "temperature_2m_max": [24.1, 26.0, 22.5, 19.8],
            "weather_code": [3, 0, 61, 95]
          }
        }
        """
        let home = try makeHome(weatherJSON: json)
        await home.refreshWeather()

        let weather = try #require(home.weather)
        #expect(weather.temperatureC == 21.4)
        #expect(weather.emoji == "☁️")
        #expect(weather.condition == "Overcast")
        #expect(weather.forecast.count == 3)
        #expect(weather.forecast[0].emoji == "☀️")
        #expect(weather.forecast[1].emoji == "🌧️")
        #expect(weather.forecast[2].emoji == "⛈️")
    }

    @Test func weatherFailureKeepsLastValue() async throws {
        let home = try makeHome(weatherJSON: "not json")
        await home.refreshWeather()
        #expect(home.weather == nil)
    }
}

private struct FixedLocation: LocationProviding {
    func currentLocation() async throws -> Coordinates {
        Coordinates(latitude: 50.45, longitude: 30.52)
    }
}
