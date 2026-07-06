import SwiftUI
import SphereCore

public struct HomeScreen: View {
    private let store: HomeStore
    private let userName: String
    private let onConfigureProvider: (() -> Void)?
    private let onQuickCapture: ((String) async -> [CaptureResult])?
    private let onAgentCapture: ((String, [Data]) async -> CaptureOutcome)?
    private let ritual: RitualStore?
    private let insights: InsightsStore?
    private let nudges: NudgeStore?
    private let reviews: ReviewStore?
    private let experiments: ExperimentStore?
    private let readiness: ReadinessStore?
    private let agent: AgentService?
    private let search: SearchStore?

    @State private var showingCapture = false
    @State private var showingAgent = false
    @State private var showingRitual = false
    @State private var showingWeeklyReview = false
    @State private var showingLifeWheel = false
    @State private var showingExperiments = false
    @State private var showingPatterns = false
    @State private var quickConfirm: String?
    @State private var quickTick = 0

    /// `onConfigureProvider` is called when the user taps the keyless Meta
    /// Agent card; the app target routes it to Settings. `onQuickCapture`, when
    /// provided, shows a `+` toolbar button that opens quick capture. Focus
    /// rows and the Life Score chips navigate via `SphereType` values — the
    /// enclosing NavigationStack must register `navigationDestination(for:
    /// SphereType.self)`.
    public init(
        store: HomeStore,
        userName: String = "",
        onConfigureProvider: (() -> Void)? = nil,
        onQuickCapture: ((String) async -> [CaptureResult])? = nil,
        onAgentCapture: ((String, [Data]) async -> CaptureOutcome)? = nil,
        ritual: RitualStore? = nil,
        insights: InsightsStore? = nil,
        nudges: NudgeStore? = nil,
        reviews: ReviewStore? = nil,
        experiments: ExperimentStore? = nil,
        readiness: ReadinessStore? = nil,
        agent: AgentService? = nil,
        search: SearchStore? = nil
    ) {
        self.store = store
        self.userName = userName
        self.onConfigureProvider = onConfigureProvider
        self.onQuickCapture = onQuickCapture
        self.onAgentCapture = onAgentCapture
        self.ritual = ritual
        self.insights = insights
        self.nudges = nudges
        self.reviews = reviews
        self.experiments = experiments
        self.readiness = readiness
        self.agent = agent
        self.search = search
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                LifeRingsCard(lifeScore: store.lifeScore, scores: store.scores, userName: userName)
                if store.isPaused {
                    pausedBadge
                }
                if let signal = topSignal {
                    signalLine(signal)
                }
            }
            .padding()
        }
        .navigationTitle(Text(ui: "Home"))
        .safeAreaInset(edge: .bottom) { agentBar }
        .toolbar {
            if let search {
                ToolbarItem(placement: .navigation) {
                    NavigationLink {
                        GlobalSearchScreen(store: search)
                    } label: { Image(systemName: "magnifyingglass") }
                    .accessibilityLabel(Text(ui: "Search"))
                }
            }
            ToolbarItem(placement: .primaryAction) { moreMenu }
        }
        .sheet(isPresented: $showingCapture) {
            if let onQuickCapture { QuickCaptureSheet(run: onQuickCapture) }
        }
        .sheet(isPresented: $showingAgent) { agentSheet }
        .sheet(isPresented: $showingRitual) { ritualSheet }
        .sheet(isPresented: $showingWeeklyReview) {
            if let reviews { WeeklyReviewSheet(reviews: reviews) }
        }
        .sheet(isPresented: $showingLifeWheel) {
            if let reviews { LifeWheelSheet(reviews: reviews) }
        }
        .sheet(isPresented: $showingExperiments) {
            if let experiments { ExperimentsScreen(store: experiments) }
        }
        .sheet(isPresented: $showingPatterns) {
            AgentResultSheet(
                title: uiString("Your patterns"), subtitle: uiString("Across your life, this week"),
                systemImage: "sparkles.rectangle.stack",
                tint: SphereTheme.accent(for: .mindfulness),
                agent: agent, task: .analyzePatterns(scope: "my life", facts: patternFacts()),
                onConfigureProvider: onConfigureProvider
            )
        }
        .refreshable {
            await store.refreshWeather()
            await store.refreshCalendar()
            await store.streamBrief()
        }
        .task {
            await store.refreshWeather()
            await store.refreshCalendar()
            await store.streamBrief()
        }
    }

    // MARK: - Bottom agent bar

    private var agentBar: some View {
        Button { showingAgent = true } label: {
            HStack(spacing: 10) {
                Image(systemName: "sparkles").font(.body.weight(.semibold))
                Text(ui: "Tell your agent anything").font(.callout.weight(.medium))
                Spacer()
                Image(systemName: "mic.fill")
                Image(systemName: "camera.fill")
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 15)
            .frame(maxWidth: .infinity)
            .background(
                Capsule().fill(SphereTheme.accent(for: .mindfulness).gradient)
            )
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
        .padding(.bottom, 6)
    }

    @ViewBuilder private var agentSheet: some View {
        AgentCaptureSheet(
            agentAvailable: agent?.isAvailable() ?? false,
            onConfigureProvider: onConfigureProvider,
            onCapture: { text, images in
                if let onAgentCapture { return await onAgentCapture(text, images) }
                if let onQuickCapture, !text.isEmpty {
                    return CaptureOutcome(results: await onQuickCapture(text))
                }
                return CaptureOutcome(results: [])
            }
        )
    }

    private var moreMenu: some View {
        Menu {
            if onQuickCapture != nil {
                Button { showingCapture = true } label: {
                    Label { Text(ui: "Quick log") } icon: { Image(systemName: "bolt") }
                }
            }
            if reviews != nil {
                Button { showingWeeklyReview = true } label: {
                    Label { Text(ui: "Weekly review") } icon: { Image(systemName: "calendar.badge.clock") }
                }
                Button { showingLifeWheel = true } label: {
                    Label { Text(ui: "Life Wheel") } icon: { Image(systemName: "chart.pie") }
                }
            }
            if experiments != nil {
                Button { showingExperiments = true } label: {
                    Label { Text(ui: "Experiments") } icon: { Image(systemName: "flask") }
                }
            }
            if agent != nil {
                Button { showingPatterns = true } label: {
                    Label { Text(ui: "Analyze my patterns") } icon: { Image(systemName: "sparkles.rectangle.stack") }
                }
            }
            if ritualPhase != .none {
                Button { showingRitual = true } label: {
                    Label { Text(ui: "Daily ritual") } icon: { Image(systemName: "sun.max") }
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }

    // MARK: - One signal line

    private enum HomeSignal { case nudge(Nudge), verdict(ReadinessVerdict), insight(Correlation) }

    private var topSignal: HomeSignal? {
        if let nudge = nudges?.activeNudge { return .nudge(nudge) }
        if let readiness { return .verdict(readiness.verdict()) }
        if let insight = insights?.topInsight { return .insight(insight) }
        return nil
    }

    @ViewBuilder private func signalLine(_ signal: HomeSignal) -> some View {
        switch signal {
        case .nudge(let nudge):
            HStack(spacing: 10) {
                Image(systemName: "hand.wave.fill").foregroundStyle(SphereTheme.accent(for: .goals))
                VStack(alignment: .leading, spacing: 1) {
                    Text(nudge.title).font(.subheadline.weight(.semibold))
                    Text(nudge.body).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { Task { await nudges?.acknowledge(nudge) } } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }.buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, alignment: .leading).sphereCard()
        case .verdict(let verdict):
            HStack(spacing: 10) {
                Text("\(verdict.score)").font(.title3.weight(.bold).monospacedDigit())
                    .foregroundStyle(SphereTheme.accent(for: .health))
                VStack(alignment: .leading, spacing: 1) {
                    Text(verdict.headline).font(.subheadline.weight(.semibold))
                    Text(ui: "Focus \(verdict.focusWindow) · wind down \(verdict.windDown)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading).sphereCard()
        case .insight(let insight):
            HStack(spacing: 10) {
                Image(systemName: "lightbulb.fill").foregroundStyle(SphereTheme.accent(for: .mindfulness))
                Text(insight.phrase).font(.caption)
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading).sphereCard()
        }
    }

    private var scheduleCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label { Text(ui: "Today's schedule") } icon: { Image(systemName: "calendar") }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(SphereTheme.accent(for: .career))
            ForEach(store.todayEvents.prefix(5)) { event in
                HStack(spacing: 10) {
                    Text(CalendarContext.timeLabel(event))
                        .font(.caption.monospacedDigit().weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 52, alignment: .leading)
                    Text(event.title).font(.subheadline).lineLimit(1)
                    Spacer()
                }
            }
            if store.todayEvents.count > 5 {
                Text(ui: "+\(store.todayEvents.count - 5) more")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sphereCard()
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(greeting + (userName.isEmpty ? "" : ", \(userName)"))
                        .font(.title2.weight(.bold))
                    Text(Date(), format: .dateTime.weekday(.wide).day().month(.wide))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                LifeScoreBadge(score: store.lifeScore)
            }
            if let best = store.bestSphere, let needs = store.needsFocusSphere {
                HStack(spacing: 8) {
                    bestNeedsChip(system: "arrow.up", score: best, tint: .green)
                    bestNeedsChip(system: "arrow.down", score: needs, tint: .orange)
                    Spacer()
                }
            }
        }
    }

    private func bestNeedsChip(system: String, score: SphereScore, tint: Color) -> some View {
        NavigationLink(value: score.sphere) {
            HStack(spacing: 4) {
                Image(systemName: system).font(.caption2.weight(.bold))
                Text(score.emoji)
                Text(LocalizedStringKey(score.sphere.rawValue.capitalized))
                    .font(.caption.weight(.medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(tint.opacity(0.15), in: Capsule())
            .foregroundStyle(tint)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Quick actions

    private var quickActionsRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    quickChip("💧", "Water") { runQuickAction("water") }
                    quickChip("🧘", "Meditate") { runQuickAction("meditation 10") }
                    quickChip("➕", "Capture") { showingCapture = true }
                }
            }
            if let quickConfirm {
                Label(quickConfirm, systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .transition(.opacity)
            }
        }
        .sensoryFeedback(.success, trigger: quickTick)
        .animation(.snappy, value: quickConfirm)
    }

    private func quickChip(_ emoji: String, _ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(emoji)
                Text(ui: title).font(.subheadline.weight(.medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.background.secondary, in: Capsule())
            .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
    }

    private func runQuickAction(_ text: String) {
        guard let onQuickCapture else { return }
        quickTick += 1
        Task {
            let results = await onQuickCapture(text)
            guard let first = results.first else { return }
            quickConfirm = first.summary
            try? await Task.sleep(for: .seconds(2))
            if quickConfirm == first.summary { quickConfirm = nil }
        }
    }

    // MARK: - Daily ritual

    private var ritualPhase: RitualPhase { ritual?.phase() ?? .none }

    private var ritualCard: some View {
        Button {
            showingRitual = true
        } label: {
            HStack(spacing: 12) {
                Text(ritualPhase == .evening ? "🌙" : "☀️").font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(ui: ritualPhase == .evening ? "Close your day" : "Plan your day")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(ui: ritualPhase == .evening
                        ? "See what you did and reflect — 1 minute."
                        : "Set an intention and pick today's focus — 2 minutes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .sphereCard()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingRitual) { ritualSheet }
    }

    @ViewBuilder private var ritualSheet: some View {
        if let ritual {
            RitualSheet(
                phase: ritualPhase,
                focusItems: Array(store.focusItems.prefix(5)),
                highlights: store.todayHighlights(),
                initialIntention: ritual.today.intention,
                initialReflection: ritual.today.reflection,
                initialFocusIds: ritual.today.plannedFocusIds,
                onMorning: { intention, focusIds in
                    Task { try? await ritual.completeMorning(intention: intention, focusIds: focusIds) }
                },
                onEvening: { reflection in
                    Task { try? await ritual.completeEvening(reflection: reflection) }
                }
            )
        }
    }

    private func nudgeCard(_ nudge: Nudge) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "hand.wave.fill")
                .font(.title3)
                .foregroundStyle(SphereTheme.accent(for: .goals))
            VStack(alignment: .leading, spacing: 2) {
                Text(nudge.title).font(.subheadline.weight(.semibold))
                Text(nudge.body).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Task { await nudges?.acknowledge(nudge) }
            } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sphereCard()
    }

    private func insightCard(_ insight: Correlation) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label { Text(ui: "Insight of the week") } icon: { Image(systemName: "lightbulb.fill") }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(SphereTheme.accent(for: .mindfulness))
            Text(insight.phrase).font(.body)
            Text(ui: "Noticed across \(insight.n) days · a pattern, not proof.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sphereCard()
    }

    private var isSundayEvening: Bool {
        let comps = Calendar.current.dateComponents([.weekday, .hour], from: Date())
        return comps.weekday == 1 && (comps.hour ?? 0) >= 17
    }

    private var reviewsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isSundayEvening {
                Text(ui: "Sunday evening — a good moment to look back.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                if reviews != nil {
                    reviewButton(
                        title: "Weekly review", systemImage: "calendar.badge.clock",
                        sphere: .goals, highlight: isSundayEvening
                    ) { showingWeeklyReview = true }
                    reviewButton(
                        title: "Life Wheel", systemImage: "chart.pie.fill",
                        sphere: .mindfulness, highlight: false
                    ) { showingLifeWheel = true }
                }
                if experiments != nil {
                    reviewButton(
                        title: "Experiments", systemImage: "flask.fill",
                        sphere: .health, highlight: false
                    ) { showingExperiments = true }
                }
            }
            if agent != nil {
                Button { showingPatterns = true } label: {
                    Label { Text(ui: "Analyze my patterns") } icon: { Image(systemName: "sparkles.rectangle.stack") }
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(SphereTheme.accent(for: .mindfulness).opacity(0.12))
                        )
                        .foregroundStyle(SphereTheme.accent(for: .mindfulness))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(isPresented: $showingWeeklyReview) {
            if let reviews { WeeklyReviewSheet(reviews: reviews) }
        }
        .sheet(isPresented: $showingLifeWheel) {
            if let reviews { LifeWheelSheet(reviews: reviews) }
        }
        .sheet(isPresented: $showingExperiments) {
            if let experiments { ExperimentsScreen(store: experiments) }
        }
        .sheet(isPresented: $showingPatterns) {
            AgentResultSheet(
                title: uiString("Your patterns"),
                subtitle: uiString("Across your life, this week"),
                systemImage: "sparkles.rectangle.stack",
                tint: SphereTheme.accent(for: .mindfulness),
                agent: agent,
                task: .analyzePatterns(scope: "my life", facts: patternFacts()),
                onConfigureProvider: onConfigureProvider
            )
        }
    }

    private func patternFacts() -> [String] {
        var facts: [String] = []
        if let insights {
            facts += insights.weeklyInsights(limit: 5).map { $0.phrase }
        }
        if let reviews {
            facts += reviews.weeklyDigest()
        }
        return facts
    }

    private func todayVerdictCard(_ readiness: ReadinessStore) -> some View {
        let verdict = readiness.verdict()
        let color = verdictColor(verdict.band)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(verdict.score)")
                    .font(.title.weight(.bold).monospacedDigit())
                    .foregroundStyle(color)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verdict.headline).font(.subheadline.weight(.semibold))
                    Text(verdict.recommendation).font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 8) {
                verdictChip("bolt.fill", uiString("Focus \(verdict.focusWindow)"), color)
                verdictChip("moon.fill", uiString("Wind down \(verdict.windDown)"), color)
            }
            Divider()
            RatingSelector(
                title: uiString("How does today feel?"),
                systemImage: "figure.mind.and.body",
                selection: readiness.todayEnergy(),
                tint: color
            ) { level in
                Task { await readiness.rateEnergy(level) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sphereCard()
    }

    private func verdictChip(_ systemImage: String, _ text: String, _ color: Color) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(color.opacity(0.14)))
            .foregroundStyle(color)
    }

    private func verdictColor(_ band: ReadinessBand) -> Color {
        switch band {
        case .high: return SphereTheme.accent(for: .health)
        case .moderate: return SphereTheme.accent(for: .mindfulness)
        case .low: return .orange
        }
    }

    private func experimentCard(_ experiment: Experiment) -> some View {
        Button { showingExperiments = true } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "flask.fill")
                    .font(.title3)
                    .foregroundStyle(SphereTheme.accent(for: .health))
                VStack(alignment: .leading, spacing: 2) {
                    Text(experiment.title).font(.subheadline.weight(.semibold))
                    Text(ui: "Day \(experiment.dayNumber()) of \(experiment.durationDays) · \(experiment.daysRemaining()) to go")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .sphereCard()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func reviewButton(
        title: LocalizedStringKey, systemImage: String, sphere: SphereType,
        highlight: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage).font(.title3)
                Text(ui: title).font(.caption.weight(.medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(SphereTheme.accent(for: sphere).opacity(highlight ? 0.22 : 0.12))
            )
            .foregroundStyle(SphereTheme.accent(for: sphere))
        }
        .buttonStyle(.plain)
    }

    private var pausedBadge: some View {
        HStack(spacing: 10) {
            Text("🌿").font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(ui: "Recovery mode").font(.subheadline.weight(.semibold))
                Text(ui: "Streaks are paused and daily nudges are off. Rest up.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sphereCard()
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: uiString("Good morning")
        case 12..<18: uiString("Good afternoon")
        case 18..<23: uiString("Good evening")
        default: uiString("Good night")
        }
    }

    // MARK: - Meta Agent summary

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label { Text(ui: "Meta Agent") } icon: { Image(systemName: "sparkles") }
                    .font(.headline)
                    .foregroundStyle(SphereTheme.accent(for: .goals))
                Spacer()
                if store.briefState == .streaming {
                    ProgressView().controlSize(.small)
                }
            }
            switch store.briefState {
            case .idle:
                Text(ui: "Your daily brief will appear here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            case .streaming, .done:
                Text(store.briefText.isEmpty ? "…" : store.briefText)
                    .font(.body)
            case .failed(let message):
                if store.briefNeedsProviderKey {
                    HStack(spacing: 6) {
                        Text(message)
                        Image(systemName: "chevron.right").font(.caption2)
                    }
                    .font(.subheadline)
                    .foregroundStyle(SphereTheme.accent(for: .goals))
                } else {
                    Label(message, systemImage: "wifi.slash")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sphereCard()
        .contentShape(Rectangle())
        .onTapGesture {
            if store.briefNeedsProviderKey { onConfigureProvider?() }
        }
    }

    // MARK: - Today's Focus

    private var focusSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(ui: "Today's Focus").font(.title3.weight(.semibold))
            ForEach(store.focusItems) { item in
                NavigationLink(value: item.sphere) {
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
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .sphereCard()
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct LifeScoreBadge: View {
    let score: Int

    var body: some View {
        VStack(spacing: 2) {
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
            Text(ui: "Life").font(.caption2).foregroundStyle(.secondary)
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
            HStack(spacing: 6) {
                ForEach(weather.forecast.prefix(3), id: \.dayLabel) { day in
                    VStack(spacing: 3) {
                        Text(day.dayLabel)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                        Image(systemName: day.symbolName)
                            .symbolRenderingMode(.multicolor)
                            .font(.subheadline)
                            .frame(height: 18)
                        Text("\(Int(day.maxTemperatureC.rounded()))°")
                            .font(.caption.weight(.semibold))
                    }
                    .frame(minWidth: 38)
                    .padding(.vertical, 6)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .sphereCard()
    }
}
