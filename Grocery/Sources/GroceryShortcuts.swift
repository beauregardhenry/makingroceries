import AppIntents

/// Phrases Siri and the Shortcuts app know without any setup.
struct GroceryShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddItemIntent(),
            phrases: [
                "Add to my list in \(.applicationName)",
                "Add groceries in \(.applicationName)",
                "Add an item in \(.applicationName)",
            ],
            shortTitle: "Add Item",
            systemImageName: "cart.badge.plus"
        )
        AppShortcut(
            intent: ReadListIntent(),
            phrases: [
                "What's on my list in \(.applicationName)",
                "Read my grocery list in \(.applicationName)",
            ],
            shortTitle: "Read List",
            systemImageName: "list.bullet"
        )
        AppShortcut(
            intent: StartShoppingIntent(),
            phrases: [
                "Start shopping in \(.applicationName)",
                "I'm at the store in \(.applicationName)",
            ],
            shortTitle: "Start Shopping",
            systemImageName: "cart"
        )
    }
}
