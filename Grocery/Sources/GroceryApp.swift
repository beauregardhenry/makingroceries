import SwiftUI

@main
struct GroceryApp: App {
    @State private var store = GroceryStore()
    @State private var incoming: IncomingList?
    @AppStorage("theme") private var themeName = Theme.grey.rawValue

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
                .onOpenURL { url in
                    if let export = GroceryStore.readExport(from: url) { incoming = IncomingList(export: export) }
                }
                .sheet(item: $incoming) { ImportListView(incoming: $0).environment(store) }
                .preferredColorScheme((Theme(rawValue: themeName) ?? .grey).scheme)
                .task { await ExpiryReminders.reschedule(store.stock) }
                .onChange(of: store.stock) { _, stock in Task { await ExpiryReminders.reschedule(stock) } }
                .onChange(of: store.shops) { _, shops in ArrivalReminders.shared.syncRegions(shops) }
        }
    }
}
