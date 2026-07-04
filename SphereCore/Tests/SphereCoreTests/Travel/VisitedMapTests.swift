import Foundation
import Testing
@testable import SphereCore

@Suite("VisitedMap")
struct VisitedMapTests {
    @Test func distinctNamesDedupeAndSort() {
        let visited = [
            VisitedCountry(name: "Poland", flag: "🇵🇱"),
            VisitedCountry(name: "poland", flag: "🇵🇱"),
            VisitedCountry(name: "Japan", flag: "🇯🇵"),
        ]
        #expect(VisitedMap.distinctCountryNames(visited) == ["Japan", "Poland"])
    }

    @Test func regionNilForEmpty() {
        #expect(VisitedMap.region(fitting: []) == nil)
    }

    @Test func regionForSinglePointUsesMinSpanAndCenters() {
        let region = VisitedMap.region(fitting: [GeoCoordinate(lat: 52, lon: 21)], minSpan: 20)!
        #expect(region.centerLat == 52)
        #expect(region.centerLon == 21)
        #expect(region.spanLat == 20)
        #expect(region.spanLon == 20)
    }

    @Test func regionFitsTwoPointsWithPadding() {
        let region = VisitedMap.region(
            fitting: [GeoCoordinate(lat: 0, lon: 0), GeoCoordinate(lat: 40, lon: 60)],
            padding: 1.5, minSpan: 10
        )!
        #expect(region.centerLat == 20)
        #expect(region.centerLon == 30)
        #expect(region.spanLat == 60)   // 40 * 1.5
        #expect(region.spanLon == 90)   // 60 * 1.5
    }

    @Test func regionClampsToGlobe() {
        let region = VisitedMap.region(
            fitting: [GeoCoordinate(lat: -85, lon: -179), GeoCoordinate(lat: 85, lon: 179)],
            padding: 3
        )!
        #expect(region.spanLat == 180)
        #expect(region.spanLon == 360)
    }
}
