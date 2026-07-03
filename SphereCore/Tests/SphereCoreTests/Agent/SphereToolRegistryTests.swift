import Foundation
import Testing
@testable import SphereCore

@Suite("SphereToolRegistry")
struct SphereToolRegistryTests {
    private func makeRegistry() -> SphereToolRegistry {
        SphereToolRegistry(tools: [
            SphereTool(
                definition: LLMTool(name: "log_water_glass", description: "Log water", inputSchema: ["type": "object"]),
                spheres: [.health],
                confirmation: { input in
                    let count = input["count"]?.intValue ?? 1
                    return count == 1 ? "Logged 1 glass of water" : "Logged \(count) glasses of water"
                },
                handler: { input in
                    JSONValue.object(["ok": true, "total_today": .number(Double(input["count"]?.intValue ?? 1))]).encodedString()
                }
            ),
            SphereTool(
                definition: LLMTool(name: "list_goals", description: "List goals", inputSchema: ["type": "object"]),
                spheres: [.goals],
                silent: true,
                handler: { _ in "{\"count\":0,\"goals\":[]}" }
            ),
            SphereTool(
                definition: LLMTool(name: "always_fails", description: "Fails", inputSchema: ["type": "object"]),
                handler: { _ in throw CocoaError(.fileNoSuchFile) }
            ),
        ])
    }

    @Test func filtersToolsBySphere() {
        let registry = makeRegistry()
        let health = registry.toolsFor(.health).map(\.name)
        #expect(health.contains("log_water_glass"))
        #expect(!health.contains("list_goals"))
        // Sphere-less tools are offered everywhere.
        #expect(health.contains("always_fails"))
        #expect(registry.toolsFor(nil).count == 3)
    }

    @Test func executesHandlerAndReturnsContent() async {
        let registry = makeRegistry()
        let result = await registry.execute(
            LLMToolCall(id: "c1", name: "log_water_glass", input: ["count": 2])
        )
        #expect(!result.isError)
        #expect(JSONValue.decoded(from: result.content)?["ok"]?.boolValue == true)
    }

    @Test func unknownToolIsErrorNotCrash() async {
        let registry = makeRegistry()
        let result = await registry.execute(LLMToolCall(id: "c1", name: "nope", input: .object([:])))
        #expect(result.isError)
        #expect(result.content.contains("Unknown tool"))
    }

    @Test func throwingHandlerBecomesErrorResult() async {
        let registry = makeRegistry()
        let result = await registry.execute(LLMToolCall(id: "c1", name: "always_fails", input: .object([:])))
        #expect(result.isError)
    }

    @Test func confirmationLabels() {
        let registry = makeRegistry()
        #expect(
            registry.confirmation(for: LLMToolCall(id: "c", name: "log_water_glass", input: ["count": 3]))
                == "Logged 3 glasses of water"
        )
        #expect(registry.confirmation(for: LLMToolCall(id: "c", name: "list_goals", input: .object([:]))) == nil)
        #expect(registry.confirmation(for: LLMToolCall(id: "c", name: "unknown", input: .object([:]))) == nil)
    }
}
