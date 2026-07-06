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
        session.onReachable = { [weak self] in
            self?.drainPendingLogs()
        }
        session.activate()
        // A widget-button tap while the app was closed left commands queued;
        // drain them now (they'll go live if reachable, else re-queue).
        drainPendingLogs()
    }

    private func apply(_ new: WidgetSnapshot) {
        snapshot = new
        WidgetSnapshotStore.shared()?.write(new)
        WidgetCenter.shared.reloadAllTimelines()
        // The phone just spoke to us, so it's reachable — flush any logs the
        // widget queued while the app wasn't running.
        drainPendingLogs()
    }

    /// Sends every command the watch widget extension queued (it can't reach
    /// the phone itself) to the phone. Idempotent: `drain()` clears the queue,
    /// and anything that couldn't go out live is re-queued for the next wake.
    private func drainPendingLogs() {
        guard let store = PendingWatchLogStore.shared() else { return }
        for command in store.drain() where !session.send(command) {
            store.enqueue(command)
        }
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
    /// Fired when the phone becomes reachable, so queued widget logs can flush.
    var onReachable: (@MainActor () -> Void)?

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
    ) {
        guard activationState == .activated, session.isReachable else { return }
        DispatchQueue.main.async { [onReachable] in
            MainActor.assumeIsolated { onReachable?() }
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        guard session.isReachable else { return }
        DispatchQueue.main.async { [onReachable] in
            MainActor.assumeIsolated { onReachable?() }
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let snapshot = WatchPayload.decode(applicationContext) else { return }
        DispatchQueue.main.async { [onSnapshot] in
            MainActor.assumeIsolated { onSnapshot?(snapshot) }
        }
    }
}
