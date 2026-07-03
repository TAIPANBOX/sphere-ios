import Foundation
import Observation

public struct ChatMessage: Sendable, Equatable, Identifiable {
    public let id: String
    public var content: String
    public let isUser: Bool
    public let timestamp: Date
    public var isTyping: Bool
    public var isStreaming: Bool
    public var isToolConfirmation: Bool
    public var isError: Bool
    public var images: [LLMImage]

    public init(
        id: String,
        content: String,
        isUser: Bool,
        timestamp: Date = Date(),
        isTyping: Bool = false,
        isStreaming: Bool = false,
        isToolConfirmation: Bool = false,
        isError: Bool = false,
        images: [LLMImage] = []
    ) {
        self.id = id
        self.content = content
        self.isUser = isUser
        self.timestamp = timestamp
        self.isTyping = isTyping
        self.isStreaming = isStreaming
        self.isToolConfirmation = isToolConfirmation
        self.isError = isError
        self.images = images
    }
}

/// One conversation with a sphere agent: message list state machine over
/// ``AgentService/chat``. Ported from the Flutter `_ChatNotifier` including
/// its bubble mechanics — a typing bubble that turns into the streaming
/// reply, tool-confirmation chips, and a fresh bubble for post-tool text.
@MainActor
@Observable
public final class ChatSession {
    public private(set) var messages: [ChatMessage] = []
    public private(set) var isBusy = false

    public let sphereName: String
    public let sphereType: SphereType?
    public var userName: String
    public var userContext: String

    private let agent: AgentService
    private let tools: SphereToolRegistry?
    private var counter = 0

    public init(
        sphereName: String,
        sphereType: SphereType?,
        agent: AgentService,
        tools: SphereToolRegistry? = nil,
        userName: String = "",
        userContext: String = ""
    ) {
        self.sphereName = sphereName
        self.sphereType = sphereType
        self.agent = agent
        self.tools = tools
        self.userName = userName
        self.userContext = userContext
        addGreeting()
    }

    private func addGreeting() {
        let greeting = sphereName == "Health"
            ? "Hey! I'm your Health agent 🫀\n\nHow are you feeling today?"
            : "Hey! I'm your \(sphereName) agent. What's on your mind?"
        messages = [ChatMessage(id: nextId("greeting"), content: greeting, isUser: false)]
    }

    /// Conversation history for the model: greeting, typing bubbles, and
    /// tool chips excluded; image-only messages become a placeholder.
    func buildHistory() -> [LLMMessage] {
        messages
            .dropFirst()
            .filter { !$0.isTyping && !$0.isToolConfirmation && (!$0.content.isEmpty || !$0.images.isEmpty) }
            .map { message in
                let content = message.content.isEmpty && !message.images.isEmpty
                    ? "[shared \(message.images.count) image\(message.images.count > 1 ? "s" : "")]"
                    : message.content
                return LLMMessage(role: message.isUser ? .user : .assistant, text: content)
            }
    }

    public func send(_ content: String, images: [LLMImage] = []) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }

        let history = buildHistory()
        messages.append(ChatMessage(
            id: nextId("user"), content: content, isUser: true, images: images
        ))

        var activeId = nextId("agent")
        messages.append(ChatMessage(id: activeId, content: "", isUser: false, isTyping: true))

        do {
            var started = false
            let stream = agent.chat(
                sphere: sphereName,
                message: content,
                userName: userName,
                userContext: userContext,
                history: history,
                images: images,
                tools: tools,
                sphereType: sphereType
            )
            for try await event in stream {
                switch event {
                case .text(let text):
                    // Some models emit a literal backslash-n; normalize it.
                    let decoded = text.replacingOccurrences(of: "\\n", with: "\n")
                    if started {
                        update(activeId) { $0.content += decoded }
                    } else {
                        started = true
                        update(activeId) {
                            $0.content = decoded
                            $0.isTyping = false
                            $0.isStreaming = true
                        }
                    }

                case .tool(let confirmation, let isError):
                    // If the model called the tool before any text, the
                    // active bubble is still an empty typing indicator —
                    // drop it instead of leaving it hanging (a latent bug in
                    // the Dart version).
                    messages.removeAll { $0.id == activeId && $0.content.isEmpty && $0.isTyping }
                    update(activeId) { $0.isStreaming = false }
                    messages.append(ChatMessage(
                        id: nextId("tool"), content: confirmation, isUser: false,
                        isToolConfirmation: true, isError: isError
                    ))
                    // Post-tool text lands in a fresh bubble.
                    activeId = nextId("agent")
                    messages.append(ChatMessage(
                        id: activeId, content: "", isUser: false, isTyping: true
                    ))
                    started = false

                case .end:
                    // Drop the trailing bubble if nothing landed in it.
                    messages.removeAll { $0.id == activeId && $0.content.isEmpty && $0.isTyping }
                    update(activeId) { $0.isStreaming = false }
                }
            }
        } catch AgentError.noApiKey {
            failBubble(activeId, "Connect an AI agent in **Settings → AI Agents** to chat.")
        } catch AgentError.api(let message) {
            failBubble(activeId, "AI error: \(message)")
        } catch AgentError.backendUnavailable {
            failBubble(activeId, "Could not reach the AI provider. Check your connection and try again.")
        } catch {
            failBubble(activeId, "Something went wrong. Please try again.")
        }
    }

    public func reset() {
        addGreeting()
    }

    // MARK: - Helpers

    private func update(_ id: String, _ mutate: (inout ChatMessage) -> Void) {
        messages = messages.map { message in
            guard message.id == id else { return message }
            var copy = message
            mutate(&copy)
            return copy
        }
    }

    private func failBubble(_ id: String, _ text: String) {
        if messages.contains(where: { $0.id == id }) {
            update(id) {
                $0.content = text
                $0.isTyping = false
                $0.isStreaming = false
                $0.isError = true
            }
        } else {
            messages.append(ChatMessage(
                id: nextId("error"), content: text, isUser: false, isError: true
            ))
        }
    }

    private func nextId(_ prefix: String) -> String {
        counter += 1
        return "\(prefix)_\(counter)"
    }
}
