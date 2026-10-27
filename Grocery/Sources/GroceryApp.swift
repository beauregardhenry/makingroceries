import SwiftUI

@main
struct GroceryApp: App {
    @State private var store = GroceryStore()

    init() {
        Theme.migrateLegacyAppearance()
        // Created at launch so iOS can wake the app for a store arrival.
        _ = ArrivalReminders.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .task {
                    ArrivalReminders.shared.syncRegions(store.shops)
                    PhoneSession.shared.start(store: store)
                }
                .onChange(of: store.items) { _, _ in PhoneSession.shared.push() }
                .onChange(of: store.shops) { _, shops in ArrivalReminders.shared.syncRegions(shops) }
        }
    }
}
