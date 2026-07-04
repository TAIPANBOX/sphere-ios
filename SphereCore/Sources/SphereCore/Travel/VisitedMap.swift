import Foundation

/// A plain lat/lon pair so the region math stays free of CoreLocation/MapKit
/// and testable.
public struct GeoCoordinate: Sendable, Equatable {
    public let lat: Double
    public let lon: Double
    public init(lat: Double, lon: Double) {
        self.lat = lat
        self.lon = lon
    }
}

/// A map region as center + span (degrees), mapped to `MKCoordinateRegion` in
/// the UI layer.
public struct MapRegion: Sendable, Equatable {
    public let centerLat: Double
    public let centerLon: Double
    public let spanLat: Double
    public let spanLon: Double
}

/// Pure helpers for the visited-countries map.
public enum VisitedMap {
    /// Distinct visited-country names (deduped case-insensitively, sorted).
    public static func distinctCountryNames(_ visited: [VisitedCountry]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for country in visited {
            let key = country.name.trimmingCharacters(in: .whitespaces).lowercased()
            guard !key.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(country.name)
        }
        return result.sorted()
    }

    /// Smallest region centred on the coordinates, padded so pins aren't at the
    /// very edge and never smaller than `minSpan`. Nil when there are none.
    public static func region(
        fitting coords: [GeoCoordinate], padding: Double = 1.4, minSpan: Double = 20
    ) -> MapRegion? {
        guard !coords.isEmpty else { return nil }
        let lats = coords.map(\.lat)
        let lons = coords.map(\.lon)
        let minLat = lats.min()!, maxLat = lats.max()!
        let minLon = lons.min()!, maxLon = lons.max()!
        let spanLat = min(max((maxLat - minLat) * padding, minSpan), 180)
        let spanLon = min(max((maxLon - minLon) * padding, minSpan), 360)
        return MapRegion(
            centerLat: (minLat + maxLat) / 2,
            centerLon: (minLon + maxLon) / 2,
            spanLat: spanLat,
            spanLon: spanLon
        )
    }
}
