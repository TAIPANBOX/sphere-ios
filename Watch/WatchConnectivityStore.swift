import Foundation
import Observation
import WidgetKit
import WatchConnectivity
import SphereCore

/// Watch side of the phone→watch link. `WatchSession` is a plain
/// WCSessionDelegate (kept separate from the observable model so the
/// @Observable macro never has to satisfy the delegate protocol); it hands
/// decoded snapshots to `WatchModel`, which publishes them to the UI,
/// persists them to the watch App Group, and reloads the complication.
@MainActor
@Observable
final class WatchModel {
    private(set) var snapshot: WidgetSnapshot
    private let session = WatchSession()

    init() {
        snapshot = WidgetSnapshotStore.shared()?.read() ?? .placeholder
        session.onSnapshot = { [weak self] snapshot in
            self?.apply(snapshot)
        }
        session.activate()
    }

    private func apply(_ new: WidgetSnapshot) {
        snapshot = new
        WidgetSnapshotStore.shared()?.write(new)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Sends a quick-log command to the phone (live if reachable, else
    /// queued for the next wake). Returns whether it went out live —
    /// callers use this to show a "will sync later" hint when it didn't.
    @discardableResult
    func send(_ command: WatchCommand) -> Bool {
        session.send(command)
    }
}

/// Isolated WCSession plumbing. Delivers snapshots on the main queue.
final class WatchSession: NSObject, WCSessionDelegate {
    var onSnapshot: (@MainActor (WidgetSnapshot) -> Void)?

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Sends live via `sendMessage` when the phone is reachable, else queues
    /// via `transferUserInfo` for delivery on its next wake. Returns whether
    /// it went out live.
    @discardableResult
    func send(_ command: WatchCommand) -> Bool {
        guard WCSession.isSupported() else { return false }
        let session = WCSession.default
        let payload = command.encode()
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil)
            return true
        } else {
            session.transferUserInfo(payload)
            return false
        }
    }

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: (any Error)?
    ) {}

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let snapshot = WatchPayload.decode(applicationContext) else { return }
        DispatchQueue.main.async { [onSnapshot] in
            MainActor.assumeIsolated { onSnapshot?(snapshot) }
        }
    }
}
