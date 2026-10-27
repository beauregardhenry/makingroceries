import Foundation
#if os(iOS) && canImport(ActivityKit)
import ActivityKit

/// What the lock screen and Dynamic Island show while you shop.
struct ShoppingAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var remaining: Int
        var total: Int
        var nextItem: String?
    }

    var storeName: String
}

enum ShoppingActivity {
    /// Starts, updates or ends the Live Activity to match the list. Ends it when nothing is left to
    /// buy or `active` is false.
    static func sync(storeName: String, remaining: Int, total: Int, next: String?, active: Bool) async {
        let state = ShoppingAttributes.ContentState(remaining: remaining, total: total, nextItem: next)
        let current = Activity<ShoppingAttributes>.activities.first

        guard active, total > 0 else {
            for activity in Activity<ShoppingAttributes>.activities { await activity.end(nil, dismissalPolicy: .immediate) }
            return
        }
        if remaining == 0 {
            await current?.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .after(.now + 120))
            return
        }
        if let current, current.attributes.storeName == storeName {
            await current.update(ActivityContent(state: state, staleDate: nil))
            return
        }
        for activity in Activity<ShoppingAttributes>.activities { await activity.end(nil, dismissalPolicy: .immediate) }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        _ = try? Activity.request(attributes: ShoppingAttributes(storeName: storeName),
                                  content: ActivityContent(state: state, staleDate: nil))
    }
}
#endif
