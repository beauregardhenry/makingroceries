import SwiftUI
import WatchConnectivity

@main
struct GroceryWatchApp: App {
    @State private var model = WatchModel()

    var body: some Scene {
        WindowGroup {
            WatchListView().environment(model)
        }
    }
}

/// The watch's copy of your lists, kept up to date by the iPhone. Runs on the main thread; WatchConnectivity
/// calls in from its own thread, and only plain values (a decoded snapshot, a true/false) are handed across.
@MainActor
@Observable
final class WatchModel: NSObject, WCSessionDelegate {
    var snapshot = WatchSnapshot(groups: [])
    var isReachable = false
    private static let cacheKey = "snapshot"
    private static let isDemo = ProcessInfo.processInfo.arguments.contains("-demo")

    override init() {
        super.init()
        if let data = UserDefaults.standard.data(forKey: Self.cacheKey),
           let cached = try? JSONDecoder().decode(WatchSnapshot.self, from: data) {
            snapshot = cached
        }
        // Screenshots and simulator checks, where there's no paired iPhone to send a list.
        if Self.isDemo {
            snapshot = .demo
            return
        }
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func toggle(_ entry: WatchSnapshot.Entry) {
        // Show the change at once; the phone confirms it with a fresh snapshot.
        snapshot.toggle(entryID: entry.id)
        guard !Self.isDemo else { return }
        save()
        let id = entry.id
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(WatchSnapshot.toggleMessage(for: id), replyHandler: nil) { _ in
                // Not reachable after all: queue it to arrive later instead.
                WCSession.default.transferUserInfo(WatchSnapshot.toggleMessage(for: id))
            }
        } else {
            WCSession.default.transferUserInfo(WatchSnapshot.toggleMessage(for: id))
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(snapshot) { UserDefaults.standard.set(data, forKey: Self.cacheKey) }
    }

    private func show(_ fresh: WatchSnapshot) {
        snapshot = fresh
        save()
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let fresh = WatchSnapshot(context: session.receivedApplicationContext)
        let reachable = session.isReachable
        Task { @MainActor in
            if let fresh { self.show(fresh) }
            self.isReachable = reachable
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let fresh = WatchSnapshot(context: applicationContext) else { return }
        Task { @MainActor in self.show(fresh) }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in self.isReachable = reachable }
    }
}
