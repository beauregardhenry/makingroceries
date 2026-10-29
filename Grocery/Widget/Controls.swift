import AppIntents
import SwiftUI
import WidgetKit

/// A Control Center, Lock Screen and Action button control that opens the app ready to add items.
struct QuickAddControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.beauregardhenry.makingroceries.quickadd") {
            ControlWidgetButton(action: OpenQuickAddIntent()) {
                Label("Add to List", systemImage: "cart.badge.plus")
            }
        }
        .displayName("Add to Grocery List")
        .description("Opens Makin' Groceries ready to type or dictate items.")
    }
}

/// A control that opens the app in Shopping Mode, on the store you're at.
struct StartShoppingControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.beauregardhenry.makingroceries.shopping") {
            ControlWidgetButton(action: StartShoppingIntent()) {
                Label("Start Shopping", systemImage: "cart")
            }
        }
        .displayName("Start Shopping")
        .description("Opens your list in Shopping Mode, on the store you're at.")
    }
}
