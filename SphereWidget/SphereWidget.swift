import WidgetKit
import SwiftUI
import SphereCore

// MARK: - Timeline

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: Date(), snapshot: current()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let entry = SnapshotEntry(date: Date(), snapshot: current())
        // The app reloads the timeline whenever data changes; refresh in an
        // hour as a fallback so the widget never goes stale for long.
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func current() -> WidgetSnapshot {
        WidgetSnapshotStore.shared()?.read() ?? .placeholder
    }
}

// MARK: - Views

private let accent = Color(red: 10 / 255, green: 132 / 255, blue: 1)

struct LifeScoreView: View {
    let snapshot: WidgetSnapshot
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .systemMedium:
            medium
        default:
            small
        }
    }

    private var ring: some View {
        ZStack {
            Circle().stroke(Color.secondary.opacity(0.2), lineWidth: 7)
            Circle()
                .trim(from: 0, to: Double(snapshot.lifeScore) / 100)
                .stroke(accent, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(snapshot.lifeScore)").font(.title2.weight(.bold))
                Text("Life").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                ring.frame(width: 58, height: 58)
                Spacer()
            }
            Spacer()
            HStack(spacing: 6) {
                Text("\(snapshot.bestEmoji) ↑")
                Text("\(snapshot.needsFocusEmoji) ↓")
            }
            .font(.caption2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var medium: some View {
        HStack(spacing: 16) {
            VStack(spacing: 6) {
                ring.frame(width: 68, height: 68)
                Text("\(snapshot.bestEmoji)↑  \(snapshot.needsFocusEmoji)↓")
                    .font(.caption2)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Today's Focus").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                if snapshot.topFocus.isEmpty {
                    Text("You're all set 🎉").font(.caption)
                } else {
                    ForEach(Array(snapshot.topFocus.prefix(3).enumerated()), id: \.offset) { _, item in
                        HStack(spacing: 6) {
                            Text(item.emoji)
                            Text(item.title).font(.caption).lineLimit(1)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Widget

struct LifeScoreWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SphereLifeScore", provider: SnapshotProvider()) { entry in
            LifeScoreView(snapshot: entry.snapshot)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Life Score")
        .description("Your Life Score and today's focus across all spheres.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct SphereWidgetBundle: WidgetBundle {
    var body: some Widget {
        LifeScoreWidget()
    }
}
