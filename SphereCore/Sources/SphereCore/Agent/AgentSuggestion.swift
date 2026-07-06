import Foundation

/// A tappable next step the agent proposes after a capture. `title` is the
/// short button label; `prompt` is a fully self-contained instruction the
/// agent can execute later with no conversation context — it must restate the
/// specifics (places, dates, names) so it stands on its own.
public struct AgentSuggestion: Sendable, Equatable, Codable, Identifiable {
    public let id: String
    public let title: String
    public let prompt: String

    public init(id: String, title: String, prompt: String) {
        self.id = id
        self.title = title
        self.prompt = prompt
    }
}

/// The result of an agent capture surfaced to the UI: the logged chips plus
/// any follow-up suggestions the agent proposed.
public struct CaptureOutcome: Sendable, Equatable {
    public let results: [CaptureResult]
    public let suggestions: [AgentSuggestion]

    public init(results: [CaptureResult], suggestions: [AgentSuggestion] = []) {
        self.results = results
        self.suggestions = suggestions
    }
}
