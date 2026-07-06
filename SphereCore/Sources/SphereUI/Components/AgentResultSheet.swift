import SwiftUI
import SphereCore

/// One reusable sheet for every agent-powered helper (pre-meeting briefing,
/// goal decomposition, interview prep, pattern analysis). Streams the agent's
/// response, offers regenerate, and degrades gracefully when no backend is
/// configured.
public struct AgentResultSheet: View {
    private let title: String
    private let subtitle: String?
    private let systemImage: String
    private let tint: Color
    private let agent: AgentService?
    private let task: AgentTask
    private let onConfigureProvider: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var streaming = false
    @State private var done = false
    @State private var failed = false

    public init(
        title: String,
        subtitle: String? = nil,
        systemImage: String = "sparkles",
        tint: Color = .accentColor,
        agent: AgentService?,
        task: AgentTask,
        onConfigureProvider: (() -> Void)? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.tint = tint
        self.agent = agent
        self.task = task
        self.onConfigureProvider = onConfigureProvider
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let subtitle {
                        Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                    }
                    if agent?.isAvailable() != true {
                        noBackend
                    } else {
                        resultCard
                    }
                }
                .padding()
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayModeInline()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text(ui: "Close") }
                }
                if agent?.isAvailable() == true && done {
                    ToolbarItem(placement: .primaryAction) {
                        Button { Task { await run() } } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .accessibilityLabel(Text(ui: "Regenerate"))
                    }
                }
            }
            .task { if text.isEmpty { await run() } }
        }
    }

    private var resultCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.medium)).foregroundStyle(tint)
            if text.isEmpty && streaming {
                ProgressView()
            } else if failed && text.isEmpty {
                Text(ui: "Couldn't reach the assistant. Check your connection and try again.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                Text(text.isEmpty ? "…" : text)
                    .font(.body)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sphereCard()
    }

    private var noBackend: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label { Text(ui: "Assistant is off") } icon: { Image(systemName: "sparkles") }
                .font(.subheadline.weight(.medium)).foregroundStyle(tint)
            Text(ui: "Turn on the free on-device assistant or add an API key to use this. Everything else in Sphere keeps working without it.")
                .font(.subheadline).foregroundStyle(.secondary)
            if let onConfigureProvider {
                Button {
                    dismiss()
                    onConfigureProvider()
                } label: {
                    Text(ui: "Set up the assistant")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sphereCard()
    }

    private func run() async {
        guard let agent, agent.isAvailable() else { return }
        text = ""
        streaming = true
        done = false
        failed = false
        do {
            for try await chunk in agent.assist(task) { text += chunk }
        } catch {
            failed = true
        }
        streaming = false
        done = true
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
