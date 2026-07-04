import Foundation
import SphereCore
#if canImport(MLXLMCommon)
import MLXLMCommon
import MLXLLM
#endif

/// Version-agnostic entry point for the downloaded-model backend (AI Tier 1).
/// Returns engines only on a real device with the MLX libraries present —
/// MLX needs the device GPU; the simulator can browse/download but not run.
enum LocalModelAI {
    private static let lock = NSLock()
    /// One loaded model at a time: reloading weights per request would cost
    /// tens of seconds, so the engine (and its loaded container) is cached
    /// until the active model changes.
    nonisolated(unsafe) private static var cached: (hubID: String, engine: any LLMEngine)?

    static func makeEngine(hubID: String) -> (any LLMEngine)? {
        #if canImport(MLXLMCommon) && !targetEnvironment(simulator)
        lock.lock()
        defer { lock.unlock() }
        if let cached, cached.hubID == hubID { return cached.engine }
        let engine = LocalModelEngine(hubID: hubID)
        cached = (hubID, engine)
        return engine
        #else
        return nil
        #endif
    }

    /// The MLX-backed downloader (real Hub download with progress) when
    /// available; the plain-URLSession fallback handles the simulator.
    static func makeDownloader() -> (any ModelDownloading)? {
        #if canImport(MLXLMCommon) && !targetEnvironment(simulator)
        return MLXModelService()
        #else
        return nil
        #endif
    }

    /// Nonisolated install check for the backend-selection closure: the
    /// download marker written by whichever downloader fetched the model.
    static func isInstalled(_ model: ModelInfo) -> Bool {
        guard let dir = LocalModelFiles.modelsDir else { return false }
        return FileManager.default.fileExists(
            atPath: dir.appendingPathComponent("\(model.id)/.complete").path
        )
    }
}

/// Shared bookkeeping location for downloaded-model markers, used by both the
/// URLSession fallback and the MLX downloader.
enum LocalModelFiles {
    static var modelsDir: URL? {
        let fm = FileManager.default
        guard let dir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Sphere/Models", isDirectory: true) else { return nil }
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableDir = dir
        try? mutableDir.setResourceValues(values)
        return dir
    }

    static func markInstalled(_ model: ModelInfo) {
        guard let dir = modelsDir?.appendingPathComponent(model.id, isDirectory: true) else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: dir.appendingPathComponent(".complete").path, contents: nil)
    }

    static func clearMarker(_ model: ModelInfo) {
        guard let dir = modelsDir?.appendingPathComponent(model.id, isDirectory: true) else { return }
        try? FileManager.default.removeItem(at: dir)
    }

    static func installedIDs() -> Set<String> {
        guard let dir = modelsDir,
              let entries = try? FileManager.default.contentsOfDirectory(atPath: dir.path)
        else { return [] }
        return Set(entries.filter { id in
            FileManager.default.fileExists(atPath: dir.appendingPathComponent("\(id)/.complete").path)
        })
    }
}

#if canImport(MLXLMCommon) && !targetEnvironment(simulator)

/// Runs a downloaded model locally through MLX. Text-only v1, mirroring
/// `FoundationModelsEngine`: ignores `tools` (no constrained decoding yet) and
/// emits text deltas then `.endTurn`. Never used in widget/watch extensions —
/// loading weights there would hit the memory jetsam limit.
final class LocalModelEngine: LLMEngine, @unchecked Sendable {
    private let hubID: String
    private let holder: ModelHolder

    init(hubID: String) {
        self.hubID = hubID
        self.holder = ModelHolder(hubID: hubID)
    }

    /// Serialises load-once semantics for the MLX container.
    private actor ModelHolder {
        private let hubID: String
        private var container: ModelContainer?

        init(hubID: String) { self.hubID = hubID }

        func loaded() async throws -> ModelContainer {
            if let container { return container }
            let loaded = try await LLMModelFactory.shared.loadContainer(
                configuration: ModelConfiguration(id: hubID)
            )
            container = loaded
            return loaded
        }
    }

    func stream(
        apiKey: String,
        system: String,
        messages: [LLMMessage],
        tools: [LLMTool],
        maxTokens: Int
    ) -> AsyncThrowingStream<LLMEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let container = try await holder.loaded()
                    let session = ChatSession(container, instructions: system)
                    let prompt = Self.render(messages)
                    for try await chunk in session.streamResponse(to: prompt) {
                        continuation.yield(.textDelta(chunk))
                    }
                    continuation.yield(.stop(.endTurn))
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: LLMError.api("Local model: \(error.localizedDescription)"))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func complete(
        apiKey: String,
        system: String,
        prompt: String,
        maxTokens: Int
    ) async throws -> String {
        let container = try await holder.loaded()
        let session = ChatSession(container, instructions: system)
        return try await session.respond(to: prompt)
    }

    /// Flattens the chat transcript into one prompt (same approach as the
    /// Foundation Models engine v1).
    private static func render(_ messages: [LLMMessage]) -> String {
        messages.map { message in
            switch message.role {
            case .user: "User: \(message.text)"
            case .assistant: "Assistant: \(message.text)"
            }
        }
        .joined(separator: "\n")
    }
}

/// Downloads model weights through the MLX Hub loader (real files, real
/// progress) and keeps the shared marker bookkeeping in sync.
final class MLXModelService: ModelDownloading, @unchecked Sendable {
    func installedIDs() -> Set<String> { LocalModelFiles.installedIDs() }

    func download(_ model: ModelInfo) -> AsyncThrowingStream<Double, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard ModelFit.fitsOnDisk(model: model, freeDiskMB: freeDiskMB()) else {
                        throw ModelDownloadError.notEnoughDisk
                    }
                    continuation.yield(0)
                    // loadContainer downloads (with progress) and loads; loading
                    // once also validates the weights end-to-end.
                    _ = try await LLMModelFactory.shared.loadContainer(
                        configuration: ModelConfiguration(id: model.hubID)
                    ) { progress in
                        continuation.yield(progress.fractionCompleted)
                    }
                    LocalModelFiles.markInstalled(model)
                    continuation.yield(1)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func delete(_ model: ModelInfo) {
        LocalModelFiles.clearMarker(model)
        // Best-effort removal of the Hub cache for this repo.
        if let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let hubDir = documents.appendingPathComponent("huggingface/models/\(model.hubID)", isDirectory: true)
            try? FileManager.default.removeItem(at: hubDir)
        }
    }

    func freeDiskMB() -> Int {
        let url = LocalModelFiles.modelsDir ?? URL(fileURLWithPath: NSHomeDirectory())
        let capacity = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage
        guard let bytes = capacity else { return 0 }
        return Int(bytes / 1_000_000)
    }

    func deviceRAMMB() -> Int {
        Int(ProcessInfo.processInfo.physicalMemory / 1_000_000)
    }
}

#endif
