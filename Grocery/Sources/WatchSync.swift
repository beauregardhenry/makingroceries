import Foundation
import WatchConnectivity

/// The iPhone's end of the link to the Apple Watch: sends the lists over, and applies check-offs
/// made on the wrist.
final class PhoneSession: NSObject, WCSessionDelegate {
    static let shared = PhoneSession()
    private weak var store: GroceryStore?

    func start(store: GroceryStore) {
        self.store = store
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Sends the current lists. Only the latest is kept, which is all the watch needs.
    func push() {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated,
              WCSession.default.isPaired, WCSession.default.isWatchAppInstalled, let store,
              let context = try? store.watchSnapshot().context() else { return }
        try? WCSession.default.updateApplicationContext(context)
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if activationState == .activated { DispatchQueue.main.async { self.push() } }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) { apply(message) }
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) { apply(userInfo) }

    private func apply(_ message: [String: Any]) {
        guard WatchSnapshot.toggledID(in: message) != nil else { return }
        DispatchQueue.main.async {
            guard let store = self.store else { return }
            // The app may have been in the background while the widget or Siri changed the list.
            store.reload()
            if store.applyWatchMessage(message) { self.push() }
        }
    }
}
