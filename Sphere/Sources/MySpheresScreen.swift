import SwiftUI
import SphereCore

/// One place to both enable/disable spheres and reorder them, replacing the
/// split between Settings toggles and the Spheres-tab drag. Tap Edit to drag.
struct MySpheresScreen: View {
    let container: AppContainer

    @State private var order: [SphereType] = []

    var body: some View {
        List {
            ForEach(order, id: \.self) { sphere in
                HStack(spacing: 12) {
                    Text(sphereEmoji(sphere)).font(.title3)
                    Text(LocalizedStringKey(sphere.rawValue.capitalized))
                    Spacer()
                    Toggle("", isOn: activeBinding(sphere)).labelsHidden()
                }
            }
            .onMove(perform: move)
        }
        .navigationTitle("My Spheres")
        .toolbar { EditButton() }
        .onAppear(perform: loadOrder)
    }

    /// All 12 spheres in the user's saved order (unknown ones trail in enum
    /// order), so both active and hidden spheres can be reordered here.
    private func loadOrder() {
        let saved = container.profile.profile.sphereOrder
        let rank = Dictionary(uniqueKeysWithValues: saved.enumerated().map { ($1, $0) })
        order = SphereType.allCases.sorted {
            (rank[$0.rawValue] ?? .max, indexInEnum($0)) < (rank[$1.rawValue] ?? .max, indexInEnum($1))
        }
    }

    private func indexInEnum(_ sphere: SphereType) -> Int {
        SphereType.allCases.firstIndex(of: sphere) ?? 0
    }

    private func move(from source: IndexSet, to offset: Int) {
        order.move(fromOffsets: source, toOffset: offset)
        let reordered = order
        Task { await container.reorderSpheres(reordered) }
    }

    private func activeBinding(_ sphere: SphereType) -> Binding<Bool> {
        Binding(
            get: { container.profile.profile.isSphereActive(sphere) },
            set: { active in
                Task { try? await container.profile.setSphereActive(sphere, active: active) }
            }
        )
    }
}
