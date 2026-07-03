import Foundation
#if canImport(CoreLocation)
import CoreLocation
#endif

public struct DayForecast: Sendable, Equatable {
    public let dayLabel: String
    public let emoji: String
    public let maxTemperatureC: Double
}

public struct Weather: Sendable, Equatable {
    public let temperatureC: Double
    public let weatherCode: Int
    public let forecast: [DayForecast]

    public var emoji: String {
        Self.emoji(for: weatherCode)
    }

    public var condition: String {
        Self.condition(for: weatherCode)
    }

    /// WMO weather interpretation codes (Open-Meteo).
    static func emoji(for code: Int) -> String {
        switch code {
        case 0: "☀️"
        case 1, 2: "🌤️"
        case 3: "☁️"
        case 45, 48: "🌫️"
        case 51...57: "🌦️"
        case 61...67, 80...82: "🌧️"
        case 71...77, 85, 86: "❄️"
        case 95...99: "⛈️"
        default: "🌡️"
        }
    }

    static func condition(for code: Int) -> String {
        switch code {
        case 0: "Clear"
        case 1, 2: "Partly cloudy"
        case 3: "Overcast"
        case 45, 48: "Fog"
        case 51...57: "Drizzle"
        case 61...67: "Rain"
        case 71...77, 85, 86: "Snow"
        case 80...82: "Showers"
        case 95...99: "Thunderstorm"
        default: "Weather"
        }
    }
}

public struct Coordinates: Sendable, Equatable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

public protocol LocationProviding: Sendable {
    func currentLocation() async throws -> Coordinates
}

/// Open-Meteo current weather + 3-day forecast. No API key required.
public struct WeatherService: Sendable {
    public typealias Fetch = @Sendable (URL) async throws -> Data

    private let fetch: Fetch

    public init(fetch: @escaping Fetch = { url in
        try await URLSession.shared.data(from: url).0
    }) {
        self.fetch = fetch
    }

    public func current(at coordinates: Coordinates) async throws -> Weather {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: "\(coordinates.latitude)"),
            URLQueryItem(name: "longitude", value: "\(coordinates.longitude)"),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code"),
            URLQueryItem(name: "daily", value: "temperature_2m_max,weather_code"),
            URLQueryItem(name: "forecast_days", value: "4"),
            URLQueryItem(name: "temperature_unit", value: "celsius"),
            URLQueryItem(name: "timezone", value: "auto"),
        ]
        let data = try await fetch(components.url!)
        guard let json = JSONValue.decoded(from: data),
              let temperature = json["current"]?["temperature_2m"]?.doubleValue,
              let code = json["current"]?["weather_code"]?.intValue
        else {
            throw URLError(.cannotParseResponse)
        }

        var forecast: [DayForecast] = []
        if let days = json["daily"]?["time"]?.arrayValue,
           let maxes = json["daily"]?["temperature_2m_max"]?.arrayValue,
           let codes = json["daily"]?["weather_code"]?.arrayValue {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            let dayFormatter = DateFormatter()
            dayFormatter.dateFormat = "EE"
            // Skip index 0 (today); show the next 3 days.
            for index in 1..<min(days.count, maxes.count, codes.count) {
                guard let raw = days[index].stringValue,
                      let date = formatter.date(from: raw),
                      let max = maxes[index].doubleValue,
                      let dayCode = codes[index].intValue
                else { continue }
                forecast.append(DayForecast(
                    dayLabel: dayFormatter.string(from: date),
                    emoji: Weather.emoji(for: dayCode),
                    maxTemperatureC: max
                ))
            }
        }
        return Weather(temperatureC: temperature, weatherCode: code, forecast: forecast)
    }
}

#if canImport(CoreLocation)
/// One-shot CoreLocation wrapper. `@unchecked Sendable`: the continuation is
/// guarded by a lock and CLLocationManager is confined to the delegate queue.
public final class CoreLocationProvider: NSObject, LocationProviding, CLLocationManagerDelegate, @unchecked Sendable {
    private let manager = CLLocationManager()
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Coordinates, Error>?

    override public init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    public func currentLocation() async throws -> Coordinates {
        #if os(iOS) || os(watchOS)
        manager.requestWhenInUseAuthorization()
        #endif
        return try await withCheckedThrowingContinuation { continuation in
            lock.withLock { self.continuation = continuation }
            manager.requestLocation()
        }
    }

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.first else { return }
        resume(.success(Coordinates(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        )))
    }

    public func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        resume(.failure(error))
    }

    private func resume(_ result: Result<Coordinates, Error>) {
        let continuation = lock.withLock {
            let value = self.continuation
            self.continuation = nil
            return value
        }
        continuation?.resume(with: result)
    }
}
#endif
