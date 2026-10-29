import AppIntents
import Foundation

/// What a Control Center, Lock Screen or Action button control asked for when it opened the app.
/// Kept in the shared app group, since the control may run in the widget extension.
enum PendingAction: String {
    case quickAdd, startShopping

    static let key = "pendingAction"
    static let requested = Notification.Name("PendingActionRequested")
    private static var defaults: UserDefaults { UserDefaults(suiteName: Storage.groupID) ?? .standard }

    static func request(_ action: PendingAction) {
        defaults.set(action.rawValue, forKey: key)
        NotificationCenter.default.post(name: requested, object: nil)
    }

    /// The waiting request, if any, removed so it's handled only once.
    static func take() -> PendingAction? {
        guard let raw = defaults.string(forKey: key) else { return nil }
        defaults.removeObject(forKey: key)
        return PendingAction(rawValue: raw)
    }
}

/// Opens the app with the quick-add bar ready to type or dictate.
struct OpenQuickAddIntent: AppIntent {
    static let title: LocalizedStringResource = "Quick Add to Grocery List"
    static let description = IntentDescription("Opens Makin' Groceries ready to type or dictate items.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        PendingAction.request(.quickAdd)
        return .result()
    }
}

/// Opens the app in Shopping Mode, on the store you're at if it knows.
struct StartShoppingIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Shopping"
    static let description = IntentDescription("Opens Makin' Groceries in Shopping Mode, on the store you're at.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        PendingAction.request(.startShopping)
        return .result()
    }
}
