import SwiftUI

@main
struct GroceryApp: App {
    @State private var store = GroceryStore()
    @State private var incoming: IncomingList?
    @State private var sync = HouseholdSync()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("myName") private var myName = ""
    @AppStorage("theme") private var themeName = Theme.grey.rawValue

    init() {
        if Storage.isUITesting, let id = Bundle.main.bundleIdentifier {
            // Start every UI test with default settings too.
            UserDefaults.standard.removePersistentDomain(forName: id)
        }
        Theme.migrateLegacyAppearance()
        // Created at launch so iOS can wake the app for a store arrival.
        _ = ArrivalReminders.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .environment(sync)
                .task {
                    ArrivalReminders.shared.syncRegions(store.shops)
                    PhoneSession.shared.start(store: store)
                    sync.start(store: store, name: myName)
                    SpotlightIndex.update(from: store)
                }
                .onChange(of: store.items) { _, _ in
                    PhoneSession.shared.push()
                    sync.itemsChanged()
                    SpotlightIndex.update(from: store)
                }
                .onChange(of: store.meals) { _, _ in SpotlightIndex.update(from: store) }
                .onChange(of: store.history) { _, _ in SpotlightIndex.update(from: store) }
                .onChange(of: scenePhase) { _, phase in
                    // Live sync only runs while the app is open; iOS stops it in the background anyway.
                    if phase == .active { sync.start(store: store, name: myName) } else if phase == .background { sync.stop() }
                }
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
