import UIKit
import SphereCore

/// Stores trip photos as downscaled JPEGs in the App Group container (falling
/// back to Application Support). Local-only — images never leave the device.
final class TripPhotoStorage: TripPhotoStoring, @unchecked Sendable {
    private static var directory: URL? {
        let fm = FileManager.default
        let base = fm.containerURL(
            forSecurityApplicationGroupIdentifier: WidgetSnapshotStore.appGroupID
        ) ?? fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Sphere", isDirectory: true)
        guard let dir = base?.appendingPathComponent("TripPhotos", isDirectory: true) else { return nil }
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func save(_ data: Data) -> String? {
        guard let directory = Self.directory, let image = UIImage(data: data) else { return nil }
        let filename = "\(UUID().uuidString).jpg"
        let resized = Self.downscale(image, maxDimension: 1_600)
        guard let jpeg = resized.jpegData(compressionQuality: 0.8) else { return nil }
        do {
            try jpeg.write(to: directory.appendingPathComponent(filename), options: .atomic)
            return filename
        } catch {
            return nil
        }
    }

    func fileURL(for filename: String) -> URL? {
        Self.directory?.appendingPathComponent(filename)
    }

    func delete(_ filename: String) {
        guard let url = fileURL(for: filename) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private static func downscale(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxDimension else { return image }
        let scale = maxDimension / longest
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    }
}
