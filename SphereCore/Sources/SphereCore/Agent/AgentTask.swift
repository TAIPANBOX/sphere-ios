import Foundation

/// The agent-powered helper features (EXPANSION_PLAN §4.4). Each case carries
/// the data it needs and knows how to phrase itself; `AgentService.assist`
/// turns it into a streamed response. No new infrastructure — prompts over the
/// existing engine + Engram recall.
public enum AgentTask: Sendable, Equatable {
    /// Prep me for a person before we meet (Relationships).
    case prepBriefing(contact: String, facts: [String])
    /// Break a goal into milestones and concrete first actions (Goals).
    case decomposeGoal(title: String, why: String)
    /// Tailored interview questions from a pasted job description (Career).
    case interviewQuestions(role: String, jobDescription: String)
    /// On-demand cross-sphere pattern analysis (parity, any sphere / Home).
    case analyzePatterns(scope: String, facts: [String])

    var system: String {
        switch self {
        case .prepBriefing:
            return "You are a thoughtful personal assistant helping someone reconnect. "
                + "From the facts and memories, write a warm 3 to 4 sentence briefing: who "
                + "they are, what's going on for them, and one caring thing to ask or bring up. "
                + "Plain prose, no lists. Never invent facts."
        case .decomposeGoal:
            return "You are a pragmatic coach. Break the goal into 3 to 5 concrete milestones, "
                + "each with a small first action the person could do this week. Be specific and "
                + "realistic. Use a short bullet per milestone. End with the single next step to take today."
        case .interviewQuestions:
            return "You are an experienced interviewer. From the role and job description, write "
                + "6 to 8 likely interview questions grouped as Technical, Behavioural, and "
                + "About-the-role. Keep them sharp and specific to this description. No answers yet."
        case .analyzePatterns:
            return "You are a perceptive analyst of personal data. From the facts, surface 2 to 3 "
                + "honest observations about what's working and what's slipping, and one gentle "
                + "suggestion. Ground every claim in the facts; correlation is not causation. "
                + "Short paragraphs, no hype."
        }
    }

    var prompt: String {
        switch self {
        case let .prepBriefing(contact, facts):
            let body = facts.isEmpty ? "No notes yet." : facts.joined(separator: "\n")
            return "Prep me before I see \(contact).\n\nWhat I know:\n\(body)"
        case let .decomposeGoal(title, why):
            let reason = why.isEmpty ? "" : "\nWhy it matters to me: \(why)"
            return "Help me break down this goal: \(title)\(reason)"
        case let .interviewQuestions(role, jobDescription):
            return "Role: \(role)\n\nJob description:\n\(jobDescription)"
        case let .analyzePatterns(scope, facts):
            let body = facts.isEmpty ? "Not much logged yet." : facts.joined(separator: "\n")
            return "Analyse my patterns for \(scope).\n\nRecent data:\n\(body)"
        }
    }

    /// Engram recall query, when past context sharpens the answer.
    var recallQuery: String? {
        switch self {
        case let .prepBriefing(contact, _): return contact
        case let .analyzePatterns(scope, _): return "\(scope) patterns habits mood"
        case .decomposeGoal, .interviewQuestions: return nil
        }
    }

    var maxTokens: Int {
        switch self {
        case .interviewQuestions, .decomposeGoal: return 700
        case .prepBriefing, .analyzePatterns: return 500
        }
    }

    var agentId: String {
        switch self {
        case .prepBriefing: return "relationships"
        case .decomposeGoal: return "goals"
        case .interviewQuestions: return "career"
        case .analyzePatterns: return "meta"
        }
    }

    /// How the result is filed back into Engram (nil = don't observe).
    var observeTag: (label: String, tags: [String])? {
        switch self {
        case let .prepBriefing(contact, _):
            return ("Briefing on \(contact)", ["briefing", "relationships"])
        case .decomposeGoal:
            return ("Goal plan", ["goal", "plan"])
        case .analyzePatterns:
            return ("Pattern analysis", ["analysis", "patterns"])
        case .interviewQuestions:
            return nil
        }
    }
}
