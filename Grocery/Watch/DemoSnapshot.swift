import Foundation

extension WatchSnapshot {
    /// A made-up list for the simulator and screenshots, shown when launched with `-demo`.
    static let demo = WatchSnapshot(groups: [
        Group(id: "kroger", name: "Kroger", items: [
            Entry(id: "1", name: "Bananas", quantity: 6, isChecked: true),
            Entry(id: "2", name: "Spinach", quantity: 1, isChecked: false),
            Entry(id: "3", name: "Milk", quantity: 1, note: "2%, half gallon", isChecked: false),
            Entry(id: "4", name: "Eggs", quantity: 2, isChecked: false),
            Entry(id: "5", name: "Bread", quantity: 1, isChecked: false),
        ]),
        Group(id: "walmart", name: "Walmart", items: [
            Entry(id: "6", name: "Paper towels", quantity: 1, isChecked: false),
            Entry(id: "7", name: "Dish soap", quantity: 1, isChecked: false),
        ]),
        Group(id: "any", name: "Any Store", items: [
            Entry(id: "8", name: "Coffee", quantity: 1, isChecked: true),
        ]),
    ])
}
