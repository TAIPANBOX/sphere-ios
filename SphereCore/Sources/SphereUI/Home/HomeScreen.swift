import SwiftUI
import SphereCore

public struct HomeScreen: View {
    private let store: HomeStore
    private let userName: String

    public init(store: HomeStore, userName: String = "") {
        self.store = store
        self.userName = userName
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                if let weather = store.weather {
                    WeatherBar(weather: weather)
                }
                summaryCard
                focusSection
            }
            .padding()
        }
        .navigationTitle("Home")
        .task {
            await store.refreshWeather()
            await store.streamBrief()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(greeting + (userName.isEmpty ? "" : ", \(userName)"))
                    .font(.title2.weight(.bold))
                Text(Date(), format: .dateTime.weekday(.wide).day().month(.wide))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            LifeScoreBadge(
                score: store.lifeScore,
                best: store.bestSphere,
                needsFocus: store.needsFocusSphere
            )
        }
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: "Good morning"
        case 12..<18: "Good afternoon"
        case 18..<23: "Good evening"
        default: "Good night"
        }
    }

    // MARK: - Meta Agent summary

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Meta Agent", systemImage: "sparkles")
                    .font(.headline)
                    .foregroundStyle(SphereTheme.accent(for: .goals))
                Spacer()
                if store.briefState == .streaming {
                    ProgressView().controlSize(.small)
                }
            }
            switch store.briefState {
            case .idle:
                Text("Your daily brief will appear here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            case .streaming, .done:
                Text(store.briefText.isEmpty ? "…" : store.briefText)
                    .font(.body)
            case .failed(let message):
                Label(message, systemImage: "wifi.slash")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sphereCard()
    }

    // MARK: - Today's Focus

    private var focusSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Today's Focus").font(.title3.weight(.semibold))
            ForEach(store.focusItems) { item in
                HStack(spacing: 12) {
                    Text(item.emoji).font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title).font(.body.weight(.medium))
                        Text(item.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer()
                    if let tag = item.tag {
                        Text(tag)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                SphereTheme.accent(for: item.sphere).opacity(0.15),
                                in: Capsule()
                            )
                            .foregroundStyle(SphereTheme.accent(for: item.sphere))
                    }
                }
                .sphereCard()
            }
        }
    }
}

struct LifeScoreBadge: View {
    let score: Int
    let best: SphereScore?
    let needsFocus: SphereScore?

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.15), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: Double(score) / 100)
                    .stroke(
                        SphereTheme.accent(for: .goals),
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                Text("\(score)")
                    .font(.headline.weight(.bold))
            }
            .frame(width: 54, height: 54)
            if let best, let needsFocus {
                Text("\(best.emoji) ↑ \(needsFocus.emoji) ↓")
                    .font(.caption2)
            }
        }
    }
}

struct WeatherBar: View {
    let weather: Weather

    var body: some View {
        HStack(spacing: 14) {
            Text(weather.emoji).font(.system(size: 40))
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .lastTextBaseline, spacing: 8) {
                    Text("\(Int(weather.temperatureC.rounded()))°")
                        .font(.title.weight(.bold))
                    Text(weather.condition)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            HStack(spacing: 12) {
                ForEach(weather.forecast.prefix(3), id: \.dayLabel) { day in
                    VStack(spacing: 2) {
                        Text(day.dayLabel).font(.caption2).foregroundStyle(.secondary)
                        Text(day.emoji).font(.body)
                        Text("\(Int(day.maxTemperatureC.rounded()))°").font(.caption2)
                    }
                }
            }
        }
        .sphereCard()
    }
}
