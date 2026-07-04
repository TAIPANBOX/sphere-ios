import SwiftUI
import SphereCore

public struct TravelScreen: View {
    private let store: TravelStore
    @State private var showingAddTrip = false
    @State private var showingAddWish = false

    private let accent = SphereTheme.accent(for: .travel)

    public init(store: TravelStore) {
        self.store = store
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let next = store.nextTrip() {
                    nextTripCard(next)
                }
                tripsSection
                visitedSection
                wishlistSection
            }
            .padding()
        }
        .navigationTitle("Travel")
        .toolbar {
            Menu {
                Button("Add Trip") { showingAddTrip = true }
                Button("Add Dream Destination") { showingAddWish = true }
            } label: {
                Image(systemName: "plus")
            }
        }
        .sheet(isPresented: $showingAddTrip) {
            AddTripSheet { plan in
                Task {
                    try? await store.add(plan)
                    try? await store.initPackingAndDocs(planId: plan.id)
                }
            }
        }
        .sheet(isPresented: $showingAddWish) {
            AddWishSheet { wish in
                Task { try? await store.addWishlist(wish) }
            }
        }
        .task {
            try? await store.load()
        }
    }

    // MARK: - Next trip

    private func nextTripCard(_ trip: TravelPlan) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Next Trip").font(.headline)
            HStack {
                Text(trip.emoji).font(.system(size: 36))
                VStack(alignment: .leading, spacing: 2) {
                    Text(trip.destination).font(.title3.weight(.bold))
                    if !trip.country.isEmpty {
                        Text(trip.country).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if let days = trip.daysUntil() {
                    VStack {
                        Text("\(days)")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(accent)
                        Text(days == 1 ? "day" : "days").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sphereCard()
    }

    // MARK: - Trips

    private var tripsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Trips").font(.title3.weight(.semibold))
            if store.plans.isEmpty {
                Text("No trips yet — plan one or ask your agent for ideas.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .sphereCard()
            }
            ForEach(store.plans) { plan in
                NavigationLink {
                    TripDetailView(store: store, planId: plan.id)
                } label: {
                    TripRow(plan: plan, accent: accent)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Visited

    private var visitedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Countries Visited").font(.title3.weight(.semibold))
                Spacer()
                Text("\(store.visited.count)")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(accent)
            }
            if !store.visited.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(store.visited) { country in
                        Text("\(country.flag) \(country.name)\(country.year.map { " ’\(String($0).suffix(2))" } ?? "")")
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(accent.opacity(0.1), in: Capsule())
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sphereCard()
    }

    // MARK: - Wishlist

    private var wishlistSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Dream List").font(.title3.weight(.semibold))
            ForEach(store.wishlist) { wish in
                HStack(spacing: 12) {
                    Text(wish.flag)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(wish.destination).font(.body.weight(.medium))
                        if !wish.country.isEmpty {
                            Text(wish.country).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button {
                        Task { try? await store.removeWishlist(id: wish.id) }
                    } label: {
                        Image(systemName: "xmark.circle").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .sphereCard()
            }
        }
    }
}

struct TripRow: View {
    let plan: TravelPlan
    let accent: Color

    private var packedCount: Int {
        plan.packingList.values.count { $0 }
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(plan.emoji)
            VStack(alignment: .leading, spacing: 2) {
                Text(plan.destination).font(.body.weight(.medium))
                HStack(spacing: 6) {
                    Text(plan.type.label)
                    if !plan.packingList.isEmpty {
                        Text("· packed \(packedCount)/\(plan.packingList.count)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Text(plan.status.rawValue.capitalized)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(accent.opacity(0.12), in: Capsule())
                .foregroundStyle(accent)
        }
        .sphereCard()
    }
}

struct TripDetailView: View {
    let store: TravelStore
    let planId: String

    private var plan: TravelPlan? {
        store.plans.first { $0.id == planId }
    }

    var body: some View {
        List {
            if let plan {
                Section("Packing List") {
                    ForEach(plan.packingList.keys.sorted(), id: \.self) { item in
                        checkRow(item, checked: plan.packingList[item] ?? false) {
                            Task { try? await store.togglePackingItem(planId: planId, item: item) }
                        }
                    }
                }
                Section("Documents") {
                    ForEach(plan.documents.keys.sorted(), id: \.self) { document in
                        checkRow(document, checked: plan.documents[document] ?? false) {
                            Task { try? await store.toggleDocument(planId: planId, document: document) }
                        }
                    }
                }
            }
        }
        .navigationTitle(plan?.destination ?? "Trip")
        .task {
            try? await store.initPackingAndDocs(planId: planId)
        }
    }

    private func checkRow(_ title: String, checked: Bool, onToggle: @escaping () -> Void) -> some View {
        Button(action: onToggle) {
            HStack {
                Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(checked ? .green : .secondary)
                Text(title).strikethrough(checked)
                Spacer()
            }
        }
        .buttonStyle(.plain)
    }
}

struct AddTripSheet: View {
    let onAdd: (TravelPlan) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var destination = ""
    @State private var country = ""
    @State private var type = TravelType.city
    @State private var status = TravelStatus.planned
    @State private var hasStartDate = false
    @State private var startDate = Date()

    var body: some View {
        NavigationStack {
            Form {
                TextField("Destination", text: $destination)
                TextField("Country", text: $country)
                Picker("Type", selection: $type) {
                    ForEach(TravelType.allCases, id: \.self) { type in
                        Text("\(type.emoji) \(type.label)").tag(type)
                    }
                }
                Picker("Status", selection: $status) {
                    ForEach(TravelStatus.allCases, id: \.self) { status in
                        Text(status.rawValue.capitalized).tag(status)
                    }
                }
                Toggle("Start date", isOn: $hasStartDate)
                if hasStartDate {
                    DatePicker("Departure", selection: $startDate, displayedComponents: .date)
                }
            }
            .navigationTitle("New Trip")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onAdd(TravelPlan(
                            id: TravelPlan.newID(),
                            destination: destination.trimmingCharacters(in: .whitespaces),
                            country: country.trimmingCharacters(in: .whitespaces),
                            emoji: type.emoji,
                            type: type,
                            status: status,
                            startDate: hasStartDate ? startDate : nil
                        ))
                        dismiss()
                    }
                    .disabled(destination.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

struct AddWishSheet: View {
    let onAdd: (WishlistDestination) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var destination = ""
    @State private var country = ""
    @State private var flag = "🌍"

    var body: some View {
        NavigationStack {
            Form {
                TextField("Destination", text: $destination)
                TextField("Country", text: $country)
                TextField("Flag emoji", text: $flag)
            }
            .navigationTitle("Dream Destination")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onAdd(WishlistDestination(
                            id: WishlistDestination.newID(),
                            destination: destination.trimmingCharacters(in: .whitespaces),
                            country: country.trimmingCharacters(in: .whitespaces),
                            flag: flag.isEmpty ? "🌍" : flag
                        ))
                        dismiss()
                    }
                    .disabled(destination.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

/// Minimal wrapping layout for chip rows (visited countries, profile tags).
public struct FlowLayout: Layout {
    public var spacing: CGFloat

    public init(spacing: CGFloat = 8) {
        self.spacing = spacing
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        layout(proposal: proposal, subviews: subviews).size
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let positions = layout(proposal: proposal, subviews: subviews).positions
        for (subview, position) in zip(subviews, positions) {
            subview.place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func layout(
        proposal: ProposedViewSize, subviews: Subviews
    ) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            totalWidth = max(totalWidth, x - spacing)
        }
        return (CGSize(width: totalWidth, height: y + rowHeight), positions)
    }
}
