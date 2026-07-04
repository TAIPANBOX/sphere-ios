import Foundation

/// One executed quick-capture fact, ready to render as a confirmation chip.
public struct CaptureResult: Sendable, Equatable {
    public let summary: String
    public let isError: Bool

    public init(summary: String, isError: Bool) {
        self.summary = summary
        self.isError = isError
    }
}

/// Runs quick capture: parse the text into tool calls (tier 1), execute each
/// through the sphere tool registry, and return confirmation chips. Tier-2
/// agent routing (for phrases the rules miss) is layered on at the call site
/// when a tool-capable backend is available.
public enum QuickCapture {
    public static func run(_ text: String, registry: SphereToolRegistry) async -> [CaptureResult] {
        var results: [CaptureResult] = []
        for call in CaptureRuleParser.parse(text) {
            let execution = await registry.execute(call)
            if execution.isError {
                results.append(CaptureResult(summary: "Couldn't log that", isError: true))
            } else {
                results.append(CaptureResult(
                    summary: registry.confirmation(for: call) ?? "Logged", isError: false
                ))
            }
        }
        return results
    }

    /// True when tier-1 rules can handle the text with no AI at all.
    public static func canParse(_ text: String) -> Bool {
        !CaptureRuleParser.parse(text).isEmpty
    }
}
