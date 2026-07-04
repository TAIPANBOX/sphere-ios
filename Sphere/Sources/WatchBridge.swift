import Foundation
import SphereCore
#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

/// Phone side of the phone→watch link. Activates a WCSession and pushes the
/// latest ``WidgetSnapshot`` as the application context (coalesced,
/// latest-state — ideal for a snapshot). No-op when a watch isn't available.
///
/// `@unchecked Sendable`: WCSession is thread-safe and the only mutable
/// state is the last snapshot, guarded by a lock.
final class WatchBridge: NSObject, @unchecked Sendable {
    static let shared = WatchBridge()

    #if canImport(WatchConnectivity)
    private let lock = NSLock()
    private var pending: WidgetSnapshot?

    private override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func send(_ snapshot: WidgetSnapshot) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else {
            // Not ready yet; remember the latest and flush on activation.
            lock.withLock { pending = snapshot }
            return
        }
        try? session.updateApplicationContext(WatchPayload.encode(snapshot))
    }
    #else
    private override init() { super.init() }
    func send(_ snapshot: WidgetSnapshot) {}
    #endif
}

#if canImport(WatchConnectivity)
extension WatchBridge: WCSessionDelegate {
    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: (any Error)?
    ) {
        guard activationState == .activated else { return }
        let snapshot = lock.withLock { () -> WidgetSnapshot? in
            let value = pending
            pending = nil
            return value
        }
        if let snapshot {
            try? session.updateApplicationContext(WatchPayload.encode(snapshot))
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
}
#endif
