import WidgetKit
import SwiftUI
import SphereCore

// Complications for the watch face. Read the snapshot the watch app persists
// to the shared App Group after each phone push.

struct WatchEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct WatchProvider: TimelineProvider {
    func placeholder(in context: Context) -> WatchEntry {
        WatchEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (WatchEntry) -> Void) {
        completion(WatchEntry(date: Date(), snapshot: current()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchEntry>) -> Void) {
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
        completion(Timeline(entries: [WatchEntry(date: Date(), snapshot: current())], policy: .after(next)))
    }

    private func current() -> WidgetSnapshot {
        WidgetSnapshotStore.shared()?.read() ?? .placeholder
    }
}

private let accent = Color(red: 10 / 255, green: 132 / 255, blue: 1)

struct WatchComplicationView: View {
    let snapshot: WidgetSnapshot
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryRectangular:
            rectangular
        case .accessoryInline:
            Text("Life \(snapshot.lifeScore) · \(snapshot.bestEmoji)↑ \(snapshot.needsFocusEmoji)↓")
        default:
            circular
        }
    }

    private var circular: some View {
        Gauge(value: Double(snapshot.lifeScore), in: 0...100) {
            Text("Life")
        } currentValueLabel: {
            Text("\(snapshot.lifeScore)")
        }
        .gaugeStyle(.accessoryCircular)
        .tint(accent)
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Life Score \(snapshot.lifeScore)").font(.headline)
            if let first = snapshot.topFocus.first {
                Text("\(first.emoji) \(first.title)").font(.caption2).lineLimit(1)
            } else {
                Text("\(snapshot.bestEmoji)↑  \(snapshot.needsFocusEmoji)↓").font(.caption2)
            }
        }
    }
}

struct SphereWatchComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SphereWatchLifeScore", provider: WatchProvider()) { entry in
            WatchComplicationView(snapshot: entry.snapshot)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Life Score")
        .description("Your Life Score at a glance.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

@main
struct SphereWatchWidgetBundle: WidgetBundle {
    var body: some Widget {
        SphereWatchComplication()
    }
}
