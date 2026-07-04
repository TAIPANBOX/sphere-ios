import SwiftUI
import SphereCore

@main
struct SphereWatchApp: App {
    @State private var model = WatchModel()

    var body: some Scene {
        WindowGroup {
            WatchRootView(snapshot: model.snapshot)
        }
    }
}

private let accent = Color(red: 10 / 255, green: 132 / 255, blue: 1)

struct WatchRootView: View {
    let snapshot: WidgetSnapshot

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
            }
            .padding()
        }
    }
}
