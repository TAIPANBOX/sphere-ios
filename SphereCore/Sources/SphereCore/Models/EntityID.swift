import Foundation

/// ID factory for new records: `<prefix>_<ms>_<4-char suffix>`.
///
/// The Dart app used bare millisecond timestamps; with SQLite primary keys
/// two same-millisecond creations (e.g. parallel tool calls in one agent
/// turn) would collide, so a random suffix is appended. Imported Dart ids
/// keep their original format — only new records use this one.
public enum EntityID {
    public static func make(_ prefix: String, now: Date = Date()) -> String {
        let millis = Int64(now.timeIntervalSince1970 * 1000)
        let suffix = UUID().uuidString.prefix(4).lowercased()
        return "\(prefix)_\(millis)_\(suffix)"
    }
}
