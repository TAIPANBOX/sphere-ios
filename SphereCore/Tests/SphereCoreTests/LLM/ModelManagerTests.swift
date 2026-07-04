import Foundation
import Testing
@testable import SphereCore

@Suite("ModelFit & Catalog")
struct ModelFitTests {
    @Test func catalogHasFiveCuratedModels() {
        #expect(ModelCatalog.all.count == 5)
        #expect(ModelCatalog.model(id: "llama-3.2-3b-q4")?.family == "Llama")
        #expect(ModelCatalog.model(id: "nope") == nil)
    }

    @Test func ramFitTiers() {
        let m = ModelInfo(id: "m", name: "M", family: "F", paramsB: 2, quant: "Q4",
                          sizeMB: 1000, minRAMMB: 2000, contextTokens: 8192, url: "x")
        #expect(ModelFit.ramFit(model: m, deviceRAMMB: 4000) == .comfortable)
        #expect(ModelFit.ramFit(model: m, deviceRAMMB: 2500) == .tight)
        #expect(ModelFit.ramFit(model: m, deviceRAMMB: 1500) == .insufficient)
    }

    @Test func diskFitNeedsMargin() {
        let m = ModelCatalog.all[0]  // 1000 MB
        #expect(ModelFit.fitsOnDisk(model: m, freeDiskMB: 1400))
        #expect(!ModelFit.fitsOnDisk(model: m, freeDiskMB: 1100))  // < 1000 + 300
    }

    @Test func sizeLabelFormatting() {
        #expect(ModelFit.sizeLabel(megabytes: 1600) == "1.6 GB")
        #expect(ModelFit.sizeLabel(megabytes: 620) == "620 MB")
    }
}

// MARK: - Manager

private final class FakeDownloader: ModelDownloading, @unchecked Sendable {
    var installed: Set<String>
    var deleted: [String] = []
    var progressSteps: [Double]
    var error: (any Error)?
    let ram: Int
    let disk: Int

    init(installed: Set<String> = [], progress: [Double] = [0.5, 1.0],
         error: (any Error)? = nil, ram: Int = 6000, disk: Int = 20000) {
        self.installed = installed
        self.progressSteps = progress
        self.error = error
        self.ram = ram
        self.disk = disk
    }

    func installedIDs() -> Set<String> { installed }
    func download(_ model: ModelInfo) -> AsyncThrowingStream<Double, Error> {
        AsyncThrowingStream { continuation in
            if let error {
                continuation.finish(throwing: error)
                return
            }
            for step in progressSteps { continuation.yield(step) }
            continuation.finish()
        }
    }
    func delete(_ model: ModelInfo) { deleted.append(model.id); installed.remove(model.id) }
    func freeDiskMB() -> Int { disk }
    func deviceRAMMB() -> Int { ram }
}

private final class FakePreferences: ModelPreferenceStoring, @unchecked Sendable {
    var active: String?
    init(active: String? = nil) { self.active = active }
    func activeModelID() -> String? { active }
    func setActiveModelID(_ id: String?) { active = id }
}

@Suite("ModelManager")
@MainActor
struct ModelManagerTests {
    private func manager(
        downloader: FakeDownloader = FakeDownloader(),
        prefs: FakePreferences = FakePreferences()
    ) -> ModelManager {
        ModelManager(downloader: downloader, preferences: prefs)
    }

    @Test func initReflectsInstalledAndActive() {
        let mgr = manager(
            downloader: FakeDownloader(installed: ["qwen2.5-1.5b-q4"]),
            prefs: FakePreferences(active: "qwen2.5-1.5b-q4")
        )
        #expect(mgr.state(for: ModelCatalog.all[1]) == .installed)
        #expect(mgr.installedModels.map(\.id) == ["qwen2.5-1.5b-q4"])
        #expect(mgr.activeModel?.id == "qwen2.5-1.5b-q4")
    }

    @Test func downloadProgressesToInstalled() async {
        let mgr = manager(downloader: FakeDownloader(progress: [0.3, 0.7, 1.0]))
        let model = ModelCatalog.all[0]
        await mgr.performDownload(model)
        #expect(mgr.state(for: model) == .installed)
    }

    @Test func downloadFailureSetsFailedState() async {
        struct Boom: Error {}
        let mgr = manager(downloader: FakeDownloader(error: Boom()))
        let model = ModelCatalog.all[0]
        await mgr.performDownload(model)
        if case .failed = mgr.state(for: model) {} else {
            Issue.record("expected .failed, got \(mgr.state(for: model))")
        }
    }

    @Test func removeClearsStateAndActive() {
        let downloader = FakeDownloader(installed: ["gemma-2-2b-q4"])
        let mgr = manager(downloader: downloader, prefs: FakePreferences(active: "gemma-2-2b-q4"))
        let model = ModelCatalog.model(id: "gemma-2-2b-q4")!
        mgr.remove(model)
        #expect(mgr.state(for: model) == .notInstalled)
        #expect(mgr.activeModelID == nil)
        #expect(downloader.deleted == ["gemma-2-2b-q4"])
    }

    @Test func setActivePersists() {
        let prefs = FakePreferences()
        let mgr = manager(prefs: prefs)
        mgr.setActive("phi-3.5-mini-q4")
        #expect(mgr.activeModelID == "phi-3.5-mini-q4")
        #expect(prefs.active == "phi-3.5-mini-q4")
    }

    @Test func ramAndDiskFitUseDeviceValues() {
        let mgr = manager(downloader: FakeDownloader(ram: 3000, disk: 500))
        let big = ModelCatalog.model(id: "phi-3.5-mini-q4")!  // 3500 MB RAM, 2300 MB disk
        #expect(mgr.ramFit(for: big) == .insufficient)
        #expect(mgr.fitsOnDisk(big) == false)
    }
}
