import SwiftUI
import SphereCore

/// The free, shareable "Year in Sphere" recap: a paged story of colourful cards
/// across every sphere, ending with a share card. Kept free by design — it's the
/// virality moment (Spotify Wrapped / Strava Year-in-Sport).
public struct YearInSphereScreen: View {
    private let cards: [RecapCard]
    private let stats: RecapStats
    @Environment(\.dismiss) private var dismiss

    public init(cards: [RecapCard], stats: RecapStats) {
        self.cards = cards
        self.stats = stats
    }

    public var body: some View {
        NavigationStack {
            TabView {
                ForEach(cards) { card in
                    RecapCardView(card: card).tag(card.id)
                }
                shareCard.tag("share")
            }
            .tabViewStylePage()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .navigationTitle("Year in Sphere")
            .navigationBarTitleDisplayModeInline()
        }
    }

    private var shareCard: some View {
        VStack(spacing: 20) {
            Spacer()
            Text("🌐").font(.system(size: 64))
            Text("That's your \(String(stats.year)).")
                .font(.title.weight(.bold))
                .multilineTextAlignment(.center)
            Text("Every part of your life, in one place — and it's yours to keep.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Spacer()
            ShareLink(item: YearInSphere.summaryLine(stats)) {
                Label("Share your year", systemImage: "square.and.arrow.up")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(SphereTheme.accent(for: .mindfulness), in: RoundedRectangle(cornerRadius: 16))
                    .foregroundStyle(.white)
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(gradient(for: nil))
    }

    private func gradient(for sphere: SphereType?) -> LinearGradient {
        let base = sphere.map { SphereTheme.accent(for: $0) } ?? SphereTheme.accent(for: .mindfulness)
        return LinearGradient(
            colors: [base.opacity(0.85), base.opacity(0.35)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }
}

private struct RecapCardView: View {
    let card: RecapCard

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Text(card.emoji).font(.system(size: 72))
            Text(card.value)
                .font(.system(size: 56, weight: .heavy, design: .rounded))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text(card.caption)
                .font(.title3.weight(.medium))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(.white)
        .background(
            LinearGradient(
                colors: [accent.opacity(0.9), accent.opacity(0.4)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        )
    }

    private var accent: Color {
        card.sphere.map { SphereTheme.accent(for: $0) } ?? SphereTheme.accent(for: .mindfulness)
    }
}

private extension View {
    @ViewBuilder
    func tabViewStylePage() -> some View {
        #if os(iOS)
        self.tabViewStyle(.page(indexDisplayMode: .always))
        #else
        self
        #endif
    }

    @ViewBuilder
    func navigationBarTitleDisplayModeInline() -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}
