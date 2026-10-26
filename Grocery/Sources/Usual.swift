import SwiftUI

/// Staples you buy again and again, plus anything you've bought before.
struct UsualView: View {
    @Environment(GroceryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    /// The store currently selected, if any; nil lets history pick.
    let shopID: UUID?
    @State private var newText = ""

    private func addNew() {
        for entry in QuickAdd.parse(newText) {
            store.addFavorite(name: entry.name, quantity: entry.quantity)
        }
        newText = ""
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("Add usual items: milk, eggs, rice", text: $newText)
                            .submitLabel(.done)
                            .onSubmit(addNew)
                        Button("Add", action: addNew)
                            .disabled(QuickAdd.parse(newText).isEmpty)
                    }
                }

                Section {
                    if store.favorites.isEmpty {
                        Text("Nothing yet. Add staples above, or long-press any item on your list and choose Add to Usual.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    ForEach(store.favorites) { favorite in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(favorite.name)
                                Text(favorite.quantity > 1 ? "×\(favorite.quantity) · \(favorite.aisle.rawValue)" : favorite.aisle.rawValue)
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if store.isOnList(favorite.name) {
                                Label("On list", systemImage: "checkmark")
                                    .font(.footnote).foregroundStyle(.secondary)
                            } else {
                                Button {
                                    withAnimation { store.addToList(favorite, shopID: shopID) }
                                } label: {
                                    Image(systemName: "plus.circle.fill").font(.title2)
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Add \(favorite.name) to list")
                            }
                        }
                    }
                    .onDelete { store.favorites.remove(atOffsets: $0) }
                } header: {
                    Text("Usual items")
                }

                let again = store.buyAgain()
                if !again.isEmpty {
                    Section("Buy again") {
                        ForEach(again) { past in
                            HStack {
                                Label(past.name, systemImage: past.aisle.symbol)
                                Spacer()
                                Button {
                                    withAnimation {
                                        store.addOrBump(name: past.name, shopID: shopID, inferShop: shopID == nil)
                                    }
                                } label: {
                                    Image(systemName: "plus.circle").font(.title2)
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Add \(past.name) to list")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Usual & Buy Again")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Add All Usual") {
                        withAnimation {
                            store.favorites.filter { !store.isOnList($0.name) }
                                .forEach { store.addToList($0, shopID: shopID) }
                        }
                    }
                    .disabled(store.favorites.allSatisfy { store.isOnList($0.name) })
                }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
