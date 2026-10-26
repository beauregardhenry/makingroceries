import SwiftUI

@main
struct GroceryApp: App {
    @State private var store = GroceryStore()

    init() {
        // Created at launch so iOS can wake the app for a store arrival.
        _ = ArrivalReminders.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .task { ArrivalReminders.shared.syncRegions(store.shops) }
                .onChange(of: store.shops) { _, shops in ArrivalReminders.shared.syncRegions(shops) }
        }
    }
}
