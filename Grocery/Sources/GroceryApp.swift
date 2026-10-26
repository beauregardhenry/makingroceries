import SwiftUI

@main
struct GroceryApp: App {
    @State private var store = GroceryStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
        }
    }
}
