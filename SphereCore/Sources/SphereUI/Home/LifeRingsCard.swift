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

    /// Drives the big ring's trim: starts at 0 and animates up to
    /// `lifeScore` on first appear, then eases to each subsequent value.
    @State private var animatedScore = 0
    /// Mirrors `scores`, but only populated once rings should start
    /// animating in — lets the per-row rings stagger from zero on appear.
    @State private var animatedScores: [SphereScore] = []

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        .onAppear {
            // First appear: animate the big ring in from 0 (celebrate), then
            // stagger the small rings in behind it.
            withAnimation(SphereMotion.resolve(SphereMotion.celebrate, reduceMotion: reduceMotion)) {
                animatedScore = lifeScore
            }
            revealRows()
        }
        .onChange(of: lifeScore) { _, newValue in
            withAnimation(SphereMotion.resolve(SphereMotion.gentle, reduceMotion: reduceMotion)) {
                animatedScore = newValue
            }
        }
        .onChange(of: scores) { _, newValue in
            animatedScores = newValue
        }
    }

    /// Reveals the breakdown rings with a slight stagger, capped at ~0.3s
    /// total. Under Reduce Motion all rows appear together, immediately.
    private func revealRows() {
        guard !scores.isEmpty else { return }
        guard !reduceMotion else {
            animatedScores = scores
            return
        }
        let stepNanoseconds: UInt64 = 60_000_000 // 60ms, capped below
        let maxSteps = 5 // ~0.3s total stagger
        for (index, score) in scores.enumerated() {
            let delaySteps = min(index, maxSteps)
            Task {
                try? await Task.sleep(nanoseconds: UInt64(delaySteps) * stepNanoseconds)
                withAnimation(SphereMotion.gentle) {
                    if !animatedScores.contains(where: { $0.id == score.id }) {
                        animatedScores.append(score)
                    }
                }
            }
        }
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
                    .trim(from: 0, to: max(0.001, Double(animatedScore) / 100))
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
                        .sphereAnimation(SphereMotion.snappy, value: lifeScore)
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
        let revealed = animatedScores.first { $0.id == score.id }
        let displayed = revealed ?? (reduceMotion ? score : SphereScore(
            sphere: score.sphere, emoji: score.emoji, score: 0, insight: score.insight
        ))
        return HStack(spacing: 10) {
            ZStack {
                Circle().stroke(tint.opacity(0.15), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: max(0.001, displayed.score))
                    .stroke(tint, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(score.emoji).font(.caption)
            }
            .frame(width: 34, height: 34)
            .sphereAnimation(SphereMotion.gentle, value: displayed.score)

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
