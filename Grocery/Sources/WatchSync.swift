import Foundation
import WatchConnectivity

/// The iPhone's end of the link to the Apple Watch: sends the lists over, and applies check-offs
/// made on the wrist. Runs on the main thread; WatchConnectivity calls in from its own thread, and only
/// plain values (the toggled item's ID) are handed across.
@MainActor
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

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        guard activationState == .activated else { return }
        Task { @MainActor in PhoneSession.shared.push() }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        apply(WatchSnapshot.toggledID(in: message))
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        apply(WatchSnapshot.toggledID(in: userInfo))
    }

    private nonisolated func apply(_ toggledID: String?) {
        guard let toggledID else { return }
        Task { @MainActor in
            let phone = PhoneSession.shared
            guard let store = phone.store else { return }
            // The app may have been in the background while the widget or Siri changed the list.
            store.reload()
            if store.applyWatchToggle(toggledID) { phone.push() }
        }
    }
}
