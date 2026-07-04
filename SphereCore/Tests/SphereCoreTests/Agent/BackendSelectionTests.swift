import Foundation
import Testing
@testable import SphereCore

@Suite("AgentService backend selection")
struct BackendSelectionTests {
    private func make(
        keys: [LLMProviderID: String] = [:],
        onDevice: Bool,
        localModel: Bool = false,
        preferred: AIBackend? = nil
    ) throws -> AgentService {
        AgentService(
            keyStore: InMemoryAPIKeyStore(keys),
            engram: try EngramStore.inMemory(),
            cache: InMemoryCache(),
            engineFactory: { _ in StubEngine() },
            onDeviceEngine: { onDevice ? StubEngine() : nil },
            localModelEngine: { localModel ? StubEngine() : nil },
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

    @Test func localModelMakesAgentAvailableWithoutAppleAI() throws {
        // The Tier-1 audience: no Apple Intelligence, no key — a downloaded
        // model still powers the agent.
        let agent = try make(onDevice: false, localModel: true)
        #expect(agent.isAvailable())
        #expect(agent.activeProviderName() == "Downloaded model")
    }

    @Test func autoPrefersAppleOnDeviceOverLocalModel() throws {
        let agent = try make(onDevice: true, localModel: true)
        #expect(agent.activeProviderName() == "On-device (free)")
    }

    @Test func autoPrefersLocalModelOverCloudKey() throws {
        let agent = try make(keys: [.anthropic: "sk-x"], onDevice: false, localModel: true)
        #expect(agent.activeProviderName() == "Downloaded model")
    }

    @Test func explicitLocalModelChoiceWins() throws {
        let agent = try make(
            keys: [.anthropic: "sk-x"], onDevice: true, localModel: true, preferred: .localModel
        )
        #expect(agent.activeProviderName() == "Downloaded model")
    }

    @Test func explicitLocalModelFallsBackWhenNotInstalled() throws {
        // Chose the downloaded model but deleted it → auto-resolve to on-device.
        let agent = try make(onDevice: true, localModel: false, preferred: .localModel)
        #expect(agent.activeProviderName() == "On-device (free)")
    }

    @Test func localModelStorageRoundTrips() {
        #expect(AIBackend(storageValue: "localModel") == .localModel)
        #expect(AIBackend.localModel.storageValue == "localModel")
    }

    @Test func hubIDDerivedFromCatalogURL() {
        let model = ModelCatalog.model(id: "qwen2.5-1.5b-q4")!
        #expect(model.hubID == "mlx-community/Qwen2.5-1.5B-Instruct-4bit")
    }
}
