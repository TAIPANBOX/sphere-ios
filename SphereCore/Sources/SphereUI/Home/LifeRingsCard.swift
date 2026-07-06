import SwiftUI
import SphereCore

/// The lean Home hero: one big Life Score ring surrounded by a per-sphere
/// breakdown. This is the whole "monitoring dashboard" — no other cards needed.
/// Each sphere row navigates to its screen via the enclosing NavigationStack's
/// `navigationDestination(for: SphereType.self)`.
struct LifeRingsCard: View {
    let lifeScore: Int
    let scores: [SphereScore]
    let userName: String

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default: return "Good night"
        }
    }

    var body: some View {
        VStack(spacing: 20) {
            hero
            if !scores.isEmpty {
                Divider().padding(.horizontal, 24)
                breakdown
            }
        }
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 24).fill(.ultraThinMaterial)
        )
    }

    // MARK: - Hero ring

    private var hero: some View {
        VStack(spacing: 6) {
            Text(greeting + (userName.isEmpty ? "" : ", \(userName)"))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.15), lineWidth: 12)
                Circle()
                    .trim(from: 0, to: max(0.001, Double(lifeScore) / 100))
                    .stroke(
                        AngularGradient(
                            colors: [.orange, .yellow, .green, .mint, .blue],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 12, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(lifeScore)")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())
                    Text("Life balance").font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(width: 160, height: 160)
            .padding(.top, 4)
        }
    }

    // MARK: - Per-sphere breakdown

    private var breakdown: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach(scores) { score in
                NavigationLink(value: score.sphere) {
                    sphereRow(score)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
    }

    private func sphereRow(_ score: SphereScore) -> some View {
        let pct = Int((score.score * 100).rounded())
        let tint = SphereTheme.accent(for: score.sphere)
        return HStack(spacing: 10) {
            ZStack {
                Circle().stroke(tint.opacity(0.15), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: max(0.001, score.score))
                    .stroke(tint, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(score.emoji).font(.caption)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 1) {
                Text(LocalizedStringKey(score.sphere.rawValue.capitalized))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text("\(pct)%")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}
