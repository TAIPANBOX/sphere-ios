import SwiftUI
import SphereCore

@main
struct SphereWatchApp: App {
    @State private var model = WatchModel()

    var body: some Scene {
        WindowGroup {
            WatchRootView(model: model)
        }
    }
}

private let accent = Color(red: 10 / 255, green: 132 / 255, blue: 1)

struct WatchRootView: View {
    let model: WatchModel
    private var snapshot: WidgetSnapshot { model.snapshot }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                ZStack {
                    Circle().stroke(Color.gray.opacity(0.3), lineWidth: 8)
                    Circle()
                        .trim(from: 0, to: Double(snapshot.lifeScore) / 100)
                        .stroke(accent, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text("\(snapshot.lifeScore)").font(.title2.weight(.bold))
                        Text("Life").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 90, height: 90)

                HStack(spacing: 10) {
                    Label(snapshot.bestName, systemImage: "arrow.up")
                        .foregroundStyle(.green)
                    Label(snapshot.needsFocusName, systemImage: "arrow.down")
                        .foregroundStyle(.orange)
                }
                .font(.caption2)

                if !snapshot.topFocus.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Today's Focus")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach(Array(snapshot.topFocus.prefix(3).enumerated()), id: \.offset) { _, item in
                            HStack(spacing: 6) {
                                Text(item.emoji)
                                Text(item.title).font(.caption2).lineLimit(1)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                quickLog

                if !snapshot.shopping.isEmpty {
                    shoppingList
                }

                askAgent
            }
            .padding()
        }
    }

    private var shoppingList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Shopping")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(snapshot.shopping) { item in
                Button {
                    model.send(.checkShopping(id: item.id))
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "circle")
                        Text(item.title).font(.caption2).lineLimit(1)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var askAgent: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextFieldLink(prompt: Text("Ask your agent")) {
                Label("Ask", systemImage: "mic.fill")
            } onSubmit: { text in
                let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !query.isEmpty { model.send(.askAgent(query: query)) }
            }
            .font(.caption2)
            .tint(accent)

            if let reply = snapshot.agentReply, !reply.isEmpty {
                Text(reply)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var quickLog: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Quick Log")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack {
                Button {
                    model.send(.logWater)
                } label: {
                    Label("Water", systemImage: "drop.fill")
                }
                .tint(.blue)
                Button {
                    model.send(.logMeditation(minutes: 10))
                } label: {
                    Label("10 min", systemImage: "figure.mind.and.body")
                }
                .tint(accent)
            }
            .font(.caption2)

            HStack(spacing: 6) {
                ForEach(1...5, id: \.self) { score in
                    Button("\(moodEmoji(score))") {
                        model.send(.logMood(score))
                    }
                    .buttonStyle(.plain)
                    .font(.title3)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func moodEmoji(_ score: Int) -> String {
        ["😞", "😕", "😐", "🙂", "😄"][score - 1]
    }
}
