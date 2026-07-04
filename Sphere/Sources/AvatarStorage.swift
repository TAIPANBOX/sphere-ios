import UIKit
import SphereCore

/// Stores the user's profile photo as a downscaled JPEG in the App Group
/// container (so the widget could show it later), falling back to Application
/// Support. Local-only — the image never leaves the device.
enum AvatarStorage {
    static var fileURL: URL? {
        let fm = FileManager.default
        let directory = fm.containerURL(
            forSecurityApplicationGroupIdentifier: WidgetSnapshotStore.appGroupID
        ) ?? fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Sphere", isDirectory: true)
        return directory?.appendingPathComponent("avatar.jpg")
    }

    static var image: UIImage? {
        guard let path = fileURL?.path else { return nil }
        return UIImage(contentsOfFile: path)
    }

    static var exists: Bool {
        guard let path = fileURL?.path else { return false }
        return FileManager.default.fileExists(atPath: path)
    }

    /// Downscales to a square-ish 512 px and saves as JPEG.
    static func save(_ data: Data) {
        guard let url = fileURL, let image = UIImage(data: data) else { return }
        let resized = downscale(image, maxDimension: 512)
        try? resized.jpegData(compressionQuality: 0.8)?.write(to: url, options: .atomic)
    }

    static func clear() {
        guard let url = fileURL else { return }
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
