import Foundation
import WatchConnectivity

extension GroceryStore {
    /// The lists as the watch shows them: one group per store with something on it, then "Any Store".
    func watchSnapshot() -> WatchSnapshot {
        func entries(_ items: [GroceryItem], order: [Aisle]) -> [WatchSnapshot.Entry] {
            items.sorted { (order.firstIndex(of: $0.aisle) ?? 0) < (order.firstIndex(of: $1.aisle) ?? 0) }
                .prefix(WatchSnapshot.maxItemsPerGroup)
                .map { .init(id: $0.id.uuidString, name: $0.name, quantity: $0.quantity, note: $0.note, isChecked: $0.isChecked) }
        }
        var groups: [WatchSnapshot.Group] = []
        for shop in shops {
            let mine = items.filter { $0.shopID == shop.id }
            if !mine.isEmpty { groups.append(.init(id: shop.id.uuidString, name: shop.name, items: entries(mine, order: shop.orderedAisles))) }
        }
        let loose = items.filter { $0.shopID == nil }
        if !loose.isEmpty { groups.append(.init(id: "any", name: "Any Store", items: entries(loose, order: Aisle.allCases))) }
        return WatchSnapshot(groups: groups)
    }
}

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
              let data = try? JSONEncoder().encode(store.watchSnapshot()) else { return }
        try? WCSession.default.updateApplicationContext([WatchSnapshot.contextKey: data])
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if activationState == .activated { DispatchQueue.main.async { self.push() } }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) { apply(message) }
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) { apply(userInfo) }

    private func apply(_ message: [String: Any]) {
        guard let id = message[WatchSnapshot.toggleKey] as? String else { return }
        DispatchQueue.main.async {
            guard let store = self.store, let item = store.items.first(where: { $0.id.uuidString == id }) else { return }
            store.toggle(item)
            self.push()
        }
    }
}
