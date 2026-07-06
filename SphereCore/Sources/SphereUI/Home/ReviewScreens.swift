import SwiftUI
import Charts
import SphereCore

// MARK: - Weekly Narrative Review (N5)

public struct WeeklyReviewSheet: View {
    private let reviews: ReviewStore
    @Environment(\.dismiss) private var dismiss

    @State private var digest: [String] = []
    @State private var narrative = ""
    @State private var streaming = false
    @State private var streamed = false
    @State private var reflection = ""
    @State private var saving = false

    public init(reviews: ReviewStore) { self.reviews = reviews }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    digestCard
                    narrativeCard
                    reflectionCard
                }
                .padding()
            }
            .navigationTitle("Your week")
            .navigationBarTitleDisplayModeInline()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(saving || (narrative.isEmpty && reflection.isEmpty))
                }
            }
            .task {
                digest = reviews.weeklyDigest()
                if reviews.canNarrate { await generate() }
            }
        }
    }

    private var digestCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("This week", systemImage: "calendar")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(SphereTheme.accent(for: .goals))
            if digest.isEmpty {
                Text("A quiet week — not much was logged.")
                    .font(.body).foregroundStyle(.secondary)
            } else {
                ForEach(digest, id: \.self) { line in
                    Text(line).font(.body)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sphereCard()
    }

    @ViewBuilder
    private var narrativeCard: some View {
        if reviews.canNarrate {
            VStack(alignment: .leading, spacing: 8) {
                Label("Reflection", systemImage: "sparkles")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(SphereTheme.accent(for: .mindfulness))
                if narrative.isEmpty && streaming {
                    ProgressView()
                } else {
                    Text(narrative.isEmpty ? "…" : narrative).font(.body)
                }
                if streamed && !streaming {
                    Button {
                        Task { await generate() }
                    } label: {
                        Label("Regenerate", systemImage: "arrow.clockwise").font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .sphereCard()
        }
    }

    private var reflectionCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Your note", systemImage: "square.and.pencil")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            TextField("What stood out this week?", text: $reflection, axis: .vertical)
                .lineLimit(3...6)
                .textFieldStyle(.roundedBorder)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sphereCard()
    }

    private func generate() async {
        guard let stream = reviews.narrate(digest: digest) else { return }
        narrative = ""
        streaming = true
        streamed = true
        do {
            for try await chunk in stream { narrative += chunk }
        } catch {
            if narrative.isEmpty {
                narrative = "Couldn't reach the agent — your week is summarised above."
            }
        }
        streaming = false
    }

    private func save() async {
        saving = true
        var parts: [String] = []
        if !narrative.isEmpty { parts.append(narrative) }
        if !reflection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append("My note: \(reflection)")
        }
        if parts.isEmpty { parts = digest }
        _ = try? await reviews.saveWeekly(content: parts.joined(separator: "\n\n"))
        saving = false
        dismiss()
    }
}

// MARK: - Life Wheel (N6)

public struct LifeWheelSheet: View {
    private let reviews: ReviewStore
    @Environment(\.dismiss) private var dismiss

    @State private var ratings: [SphereType: Double] = Dictionary(
        uniqueKeysWithValues: SphereType.allCases.map { ($0, 5.0) }
    )
    @State private var showResult = false
    @State private var saving = false

    public init(reviews: ReviewStore) { self.reviews = reviews }

    private var intRatings: [SphereType: Int] {
        ratings.mapValues { Int($0.rounded()) }
    }

    private var deltas: [WheelDelta] { reviews.lifeWheelDeltas(selfRatings: intRatings) }

    public var body: some View {
        NavigationStack {
            ScrollView {
                if showResult {
                    resultView
                } else {
                    ratingView
                }
            }
            .navigationTitle(showResult ? "Feeling vs data" : "Life Wheel")
            .navigationBarTitleDisplayModeInline()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if showResult {
                        Button("Save") { Task { await save() } }.disabled(saving)
                    } else {
                        Button("See gap") { withAnimation { showResult = true } }
                    }
                }
            }
        }
    }

    private var ratingView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Rate how each area of life feels right now, 1 to 10.")
                .font(.subheadline).foregroundStyle(.secondary)
                .padding(.horizontal)
            ForEach(SphereType.allCases, id: \.self) { sphere in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(sphere.rawValue.capitalized)
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Text("\(Int((ratings[sphere] ?? 5).rounded()))")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(SphereTheme.accent(for: sphere))
                    }
                    Slider(
                        value: Binding(
                            get: { ratings[sphere] ?? 5 },
                            set: { ratings[sphere] = $0 }
                        ),
                        in: 1...10, step: 1
                    )
                    .tint(SphereTheme.accent(for: sphere))
                }
                .padding(.horizontal)
            }
        }
        .padding(.vertical)
    }

    private var resultView: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let insight = LifeWheel.insight(deltas) {
                Text(insight)
                    .font(.body.weight(.medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .sphereCard()
            }
            if deltas.isEmpty {
                Text("Log a bit more data and the comparison chart will appear here.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                comparisonChart
                deltaList
            }
        }
        .padding()
    }

    private var comparisonChart: some View {
        Chart {
            ForEach(deltas, id: \.sphere) { d in
                BarMark(
                    x: .value("Sphere", d.sphere.rawValue.capitalized),
                    y: .value("Score", d.feeling)
                )
                .foregroundStyle(by: .value("Source", "Feeling"))
                .position(by: .value("Source", "Feeling"))
                BarMark(
                    x: .value("Sphere", d.sphere.rawValue.capitalized),
                    y: .value("Score", d.data)
                )
                .foregroundStyle(by: .value("Source", "Data"))
                .position(by: .value("Source", "Data"))
            }
        }
        .chartYScale(domain: 0...100)
        .chartForegroundStyleScale(["Feeling": Color.accentColor, "Data": Color.secondary])
        .frame(height: 260)
    }

    private var deltaList: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(deltas, id: \.sphere) { d in
                HStack {
                    Text(d.sphere.rawValue.capitalized).font(.subheadline)
                    Spacer()
                    Text(d.delta > 0 ? "+\(d.delta)" : "\(d.delta)")
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                        .foregroundStyle(d.delta < 0 ? Color.red : Color.green)
                }
            }
        }
        .sphereCard()
    }

    private func save() async {
        saving = true
        let lines = deltas.map {
            "\($0.sphere.rawValue.capitalized): feeling \($0.feeling), data \($0.data) (\($0.delta > 0 ? "+" : "")\($0.delta))"
        }
        let content = ([LifeWheel.insight(deltas)].compactMap { $0 } + lines)
            .joined(separator: "\n")
        _ = try? await reviews.saveLifeWheel(selfRatings: intRatings, content: content)
        saving = false
        dismiss()
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
