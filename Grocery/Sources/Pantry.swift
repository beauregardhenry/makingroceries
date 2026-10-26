import SwiftUI

/// "Do we still have this?" for your usual items, so staples aren't bought twice.
struct PantryCheckView: View {
    @Environment(GroceryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    /// The store currently selected, if any; nil lets history pick.
    let shopID: UUID?
    @State private var needed: Set<UUID> = []

    private var candidates: [Favorite] {
        store.favorites.filter { !store.isOnList($0.name) }
    }

    var body: some View {
        NavigationStack {
            List {
                if store.favorites.isEmpty {
                    Section {
                        Text("Add staples to your usual items first, then check them here before you shop.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                } else if candidates.isEmpty {
                    Section {
                        Label("Everything usual is already on your list.", systemImage: "checkmark.circle")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section {
                        ForEach(candidates) { favorite in
                            let isNeeded = needed.contains(favorite.id)
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(favorite.name)
                                    Text(favorite.aisle.rawValue).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Picker("Do you have \(favorite.name)?", selection: Binding(
                                    get: { isNeeded },
                                    set: { if $0 { needed.insert(favorite.id) } else { needed.remove(favorite.id) } }
                                )) {
                                    Text("Have it").tag(false)
                                    Text("Need it").tag(true)
                                }
                                .pickerStyle(.segmented)
                                .frame(width: 170)
                            }
                        }
                    } footer: {
                        Text("Mark what you're out of, then add it all to your list at once.")
                    }
                }
            }
            .navigationTitle("Pantry Check")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(needed.isEmpty ? "Done" : "Add \(needed.count)") {
                        for favorite in candidates where needed.contains(favorite.id) {
                            store.addToList(favorite, shopID: shopID)
                        }
                        dismiss()
                    }
                }
            }
        }
    }
}
