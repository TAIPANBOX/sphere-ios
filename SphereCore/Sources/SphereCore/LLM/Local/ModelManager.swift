import Foundation
import Observation

public enum ModelDownloadState: Equatable, Sendable {
    case notInstalled
    /// 0…1
    case downloading(progress: Double)
    case installed
    case failed(String)
}

/// Performs the actual file work (background URLSession, disk, RAM). Behind a
/// protocol so SphereCore stays free of URLSession/ProcessInfo specifics and the
/// manager is testable.
public protocol ModelDownloading: Sendable {
    func installedIDs() -> Set<String>
    /// Streams download progress 0…1, finishing when the model is on disk.
    func download(_ model: ModelInfo) -> AsyncThrowingStream<Double, Error>
    func delete(_ model: ModelInfo)
    func freeDiskMB() -> Int
    func deviceRAMMB() -> Int
}

/// Persists the user's active-model choice.
public protocol ModelPreferenceStoring: Sendable {
    func activeModelID() -> String?
    func setActiveModelID(_ id: String?)
}

/// Orchestrates the downloadable-model catalog: per-model download state, disk
/// and RAM fit, and the active selection. The heavy file/inference work lives
/// behind `ModelDownloading`; this type is the observable coordinator the
/// Settings "Models" page binds to.
@MainActor
@Observable
public final class ModelManager {
    public let catalog: [ModelInfo]
    public private(set) var states: [String: ModelDownloadState] = [:]
    public private(set) var activeModelID: String?

    private let downloader: any ModelDownloading
    private let preferences: any ModelPreferenceStoring
    private var tasks: [String: Task<Void, Never>] = [:]
    /// Bumped on cancel/restart; a download task only writes state while its
    /// captured generation is still current.
    private var generation: [String: Int] = [:]

    public init(
        catalog: [ModelInfo] = ModelCatalog.all,
        downloader: any ModelDownloading,
        preferences: any ModelPreferenceStoring
    ) {
        self.catalog = catalog
        self.downloader = downloader
        self.preferences = preferences
        let installed = downloader.installedIDs()
        for model in catalog {
            states[model.id] = installed.contains(model.id) ? .installed : .notInstalled
        }
        activeModelID = preferences.activeModelID()
    }

    public func state(for model: ModelInfo) -> ModelDownloadState {
        states[model.id] ?? .notInstalled
    }

    public func ramFit(for model: ModelInfo) -> RAMFit {
        ModelFit.ramFit(model: model, deviceRAMMB: downloader.deviceRAMMB())
    }

    public func fitsOnDisk(_ model: ModelInfo) -> Bool {
        ModelFit.fitsOnDisk(model: model, freeDiskMB: downloader.freeDiskMB())
    }

    public var installedModels: [ModelInfo] {
        catalog.filter { states[$0.id] == .installed }
    }

    public var activeModel: ModelInfo? {
        activeModelID.flatMap { id in catalog.first { $0.id == id } }
    }

    // MARK: - Actions

    /// Kicks off (or ignores if already running) a download, tracking a task so
    /// it can be cancelled. A per-model generation token invalidates a cancelled
    /// task's late writes, so a cancel-then-restart can't be clobbered by the
    /// task it replaced.
    public func startDownload(_ model: ModelInfo) {
        guard tasks[model.id] == nil, states[model.id] != .installed else { return }
        let gen = (generation[model.id] ?? 0) + 1
        generation[model.id] = gen
        tasks[model.id] = Task { [weak self] in
            await self?.performDownload(model)
            // Only clear the map entry if this task is still the current one.
            if self?.generation[model.id] == gen { self?.tasks[model.id] = nil }
        }
    }

    /// The awaitable download state machine (exposed for testing). Writes are
    /// gated on the generation captured at start, so a superseded task is inert.
    func performDownload(_ model: ModelInfo) async {
        let gen = generation[model.id] ?? 0
        setState(model.id, .downloading(progress: 0), gen: gen)
        do {
            for try await progress in downloader.download(model) {
                setState(model.id, .downloading(progress: min(max(progress, 0), 1)), gen: gen)
            }
            setState(model.id, .installed, gen: gen)
        } catch is CancellationError {
            setState(model.id, .notInstalled, gen: gen)
        } catch {
            setState(model.id, .failed(error.localizedDescription), gen: gen)
        }
    }

    private func setState(_ id: String, _ state: ModelDownloadState, gen: Int) {
        guard (generation[id] ?? 0) == gen else { return }  // superseded task — ignore
        states[id] = state
    }

    public func cancelDownload(_ model: ModelInfo) {
        tasks[model.id]?.cancel()
        tasks[model.id] = nil
        // Bump the generation so the cancelled task's in-flight writes are ignored.
        generation[model.id] = (generation[model.id] ?? 0) + 1
        states[model.id] = .notInstalled
    }

    public func remove(_ model: ModelInfo) {
        downloader.delete(model)
        states[model.id] = .notInstalled
        if activeModelID == model.id { setActive(nil) }
    }

    public func setActive(_ id: String?) {
        activeModelID = id
        preferences.setActiveModelID(id)
    }
}
