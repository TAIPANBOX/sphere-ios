import Foundation
import SphereCore

/// On-device model file management: a URLSession download to a temp file, moved
/// into Application Support (excluded from iCloud backup), plus disk / RAM
/// introspection for the fit badges. Wi-Fi is preferred via
/// `allowsExpensiveNetworkAccess = false`.
///
/// Limitations (follow-ups with the `LocalModelEngine` MLX piece): progress is
/// coarse (0 then 1 — no byte-level callback yet), the download is not resumable
/// across launches, and *running* the model is not wired here. Fetching the file
/// is real.
final class ModelDownloadService: ModelDownloading, @unchecked Sendable {
    private func directory(for model: ModelInfo) -> URL? {
        LocalModelFiles.modelsDir?.appendingPathComponent(model.id, isDirectory: true)
    }

    func installedIDs() -> Set<String> {
        LocalModelFiles.installedIDs()
    }

    func download(_ model: ModelInfo) -> AsyncThrowingStream<Double, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard ModelFit.fitsOnDisk(model: model, freeDiskMB: freeDiskMB()) else {
                        throw ModelDownloadError.notEnoughDisk
                    }
                    guard let source = URL(string: model.url), let dir = directory(for: model) else {
                        throw URLError(.badURL)
                    }
                    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                    continuation.yield(0)

                    var request = URLRequest(url: source)
                    request.allowsExpensiveNetworkAccess = false  // prefer Wi-Fi
                    let (temp, _) = try await URLSession.shared.download(for: request)

                    let destination = dir.appendingPathComponent("model.bin")
                    try? FileManager.default.removeItem(at: destination)
                    try FileManager.default.moveItem(at: temp, to: destination)
                    // Completion marker so a half-finished download isn't "installed".
                    FileManager.default.createFile(atPath: dir.appendingPathComponent(".complete").path, contents: nil)

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
        guard let dir = directory(for: model) else { return }
        try? FileManager.default.removeItem(at: dir)
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

enum ModelDownloadError: LocalizedError {
    case notEnoughDisk
    var errorDescription: String? {
        switch self {
        case .notEnoughDisk: "Not enough free space for this model."
        }
    }
}

/// Persists the active-model choice in UserDefaults.
struct ModelPreferences: ModelPreferenceStoring {
    func activeModelID() -> String? {
        UserDefaults.standard.string(forKey: Prefs.activeModel)
    }
    func setActiveModelID(_ id: String?) {
        UserDefaults.standard.set(id, forKey: Prefs.activeModel)
    }
}
