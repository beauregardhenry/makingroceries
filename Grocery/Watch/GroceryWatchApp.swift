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

    override init() {
        super.init()
        if let data = UserDefaults.standard.data(forKey: Self.cacheKey),
           let cached = try? JSONDecoder().decode(WatchSnapshot.self, from: data) {
            snapshot = cached
        }
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func toggle(_ entry: WatchSnapshot.Entry) {
        // Show the change at once; the phone confirms it with a fresh snapshot.
        for g in snapshot.groups.indices {
            if let i = snapshot.groups[g].items.firstIndex(where: { $0.id == entry.id }) {
                snapshot.groups[g].items[i].isChecked.toggle()
            }
        }
        save()
        let message = [WatchSnapshot.toggleKey: entry.id]
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
        guard let data = context[WatchSnapshot.contextKey] as? Data,
              let fresh = try? JSONDecoder().decode(WatchSnapshot.self, from: data) else { return }
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
