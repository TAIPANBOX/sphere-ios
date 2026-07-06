import SwiftUI
import MapKit
import CoreLocation
import SphereCore

/// A world map with a pin on every country the user has visited. Coordinates are
/// resolved from country names via `CLGeocoder` and cached for the session; the
/// camera is fitted with the pure `VisitedMap.region` math.
public struct VisitedMapScreen: View {
    private let visited: [VisitedCountry]
    @State private var coords: [String: CLLocationCoordinate2D] = [:]
    @State private var camera: MapCameraPosition = .automatic
    @State private var geocoding = false

    public init(visited: [VisitedCountry]) { self.visited = visited }

    private var names: [String] { VisitedMap.distinctCountryNames(visited) }

    public var body: some View {
        Map(position: $camera) {
            ForEach(names, id: \.self) { name in
                if let coordinate = coords[name] {
                    Marker("\(flag(for: name)) \(name)", coordinate: coordinate)
                        .tint(SphereTheme.accent(for: .travel))
                }
            }
        }
        .overlay(alignment: .top) { banner }
        .navigationTitle(Text(ui: "Visited"))
        .navigationBarTitleDisplayModeInline()
        .task { await geocodeAll() }
    }

    private var banner: some View {
        HStack(spacing: 8) {
            if geocoding { ProgressView().controlSize(.small) }
            Text(ui: geocoding
                 ? "Mapping \(names.count) countries…"
                 : "\(coords.count) of \(names.count) countries mapped")
                .font(.caption.weight(.medium))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .padding(.top, 10)
    }

    private func flag(for name: String) -> String {
        visited.first { $0.name == name }?.flag ?? "📍"
    }

    private func geocodeAll() async {
        guard !names.isEmpty else { return }
        geocoding = true
        let geocoder = CLGeocoder()
        for name in names where coords[name] == nil {
            if let placemarks = try? await geocoder.geocodeAddressString(name),
               let location = placemarks.first?.location {
                coords[name] = location.coordinate
            }
        }
        fitCamera()
        geocoding = false
    }

    private func fitCamera() {
        let points = coords.values.map { GeoCoordinate(lat: $0.latitude, lon: $0.longitude) }
        guard let region = VisitedMap.region(fitting: Array(points)) else { return }
        camera = .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: region.centerLat, longitude: region.centerLon),
            span: MKCoordinateSpan(latitudeDelta: region.spanLat, longitudeDelta: region.spanLon)
        ))
    }
}

private extension View {
    @ViewBuilder
    func navigationBarTitleDisplayModeInline() -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}
