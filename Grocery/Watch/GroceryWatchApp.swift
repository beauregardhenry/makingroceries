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

/// The watch's copy of your lists, kept up to date by the iPhone.
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
        let message = WatchSnapshot.toggleMessage(for: entry.id)
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(message, replyHandler: nil) { _ in
                WCSession.default.transferUserInfo(message)
            }
        } else {
            WCSession.default.transferUserInfo(message)
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(snapshot) { UserDefaults.standard.set(data, forKey: Self.cacheKey) }
    }

    private func receive(_ context: [String: Any]) {
        guard let fresh = WatchSnapshot(context: context) else { return }
        DispatchQueue.main.async {
            self.snapshot = fresh
            self.save()
        }
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        receive(session.receivedApplicationContext)
        DispatchQueue.main.async { self.isReachable = session.isReachable }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        receive(applicationContext)
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async { self.isReachable = session.isReachable }
    }
}
