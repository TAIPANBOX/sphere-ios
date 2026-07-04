import Foundation
import Testing
@testable import SphereCore

@Suite("AgentService backend selection")
struct BackendSelectionTests {
    private func make(
        keys: [LLMProviderID: String] = [:],
        onDevice: Bool,
        preferred: AIBackend? = nil
    ) throws -> AgentService {
        AgentService(
            keyStore: InMemoryAPIKeyStore(keys),
            engram: try EngramStore.inMemory(),
            cache: InMemoryCache(),
            engineFactory: { _ in StubEngine() },
            onDeviceEngine: { onDevice ? StubEngine() : nil },
            preferredBackend: { preferred }
        )
    }

    @Test func onDeviceMakesAgentAvailableWithNoKey() throws {
        let agent = try make(onDevice: true)
        #expect(agent.isAvailable())
        #expect(agent.activeProviderName() == "On-device (free)")
    }

    @Test func noKeyNoDeviceIsUnavailable() throws {
        let agent = try make(onDevice: false)
        #expect(!agent.isAvailable())
        #expect(agent.activeProviderName() == nil)
    }

    @Test func autoPrefersOnDeviceOverCloudKey() throws {
        let agent = try make(keys: [.anthropic: "sk-x"], onDevice: true)
        #expect(agent.activeProviderName() == "On-device (free)")
    }

    @Test func fallsBackToCloudKeyWhenNoDevice() throws {
        let agent = try make(keys: [.openai: "sk-x"], onDevice: false)
        #expect(agent.activeProviderName() == "ChatGPT")
    }

    @Test func explicitCloudChoiceWinsWhenKeyPresent() throws {
        let agent = try make(
            keys: [.anthropic: "sk-a"], onDevice: true, preferred: .cloud(.anthropic)
        )
        #expect(agent.activeProviderName() == "Claude")
    }

    @Test func explicitCloudChoiceFallsBackWhenKeyMissing() throws {
        // Chose Gemini but never entered a key → auto-resolve to on-device.
        let agent = try make(onDevice: true, preferred: .cloud(.gemini))
        #expect(agent.activeProviderName() == "On-device (free)")
    }
}
