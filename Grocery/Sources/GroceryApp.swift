import SwiftUI

@main
struct GroceryApp: App {
    @StateObject private var store = GroceryStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
    }
}
