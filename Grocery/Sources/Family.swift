import SwiftUI

/// A list someone sent you, waiting for you to look it over.
struct IncomingList: Identifiable {
    let id = UUID()
    let export: ListExport
}

/// Send your list to family as a small file. It opens in their copy of Makin' Groceries and merges in.
struct SendListView: View {
    @Environment(GroceryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let shopID: UUID?
    @AppStorage("myName") private var myName = ""
    @State private var onlyThisStore = true
    @State private var onlyNeeded = true
    @State private var fileURL: URL?

    private var scopedShopID: UUID? { onlyThisStore ? shopID : nil }
    private var export: ListExport {
        store.makeExport(shopID: scopedShopID, onlyUnchecked: onlyNeeded, from: myName.isEmpty ? nil : myName)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Your name (shown to them)", text: $myName)
                    if shopID != nil {
                        Toggle("Only \(store.shopName(for: shopID) ?? "this store")", isOn: $onlyThisStore)
                    }
                    Toggle("Only what's still needed", isOn: $onlyNeeded)
                } footer: {
                    Text("\(export.items.count) item\(export.items.count == 1 ? "" : "s") will be sent.")
                }

                Section {
                    if let fileURL {
                        ShareLink(item: fileURL) {
                            Label("Send List…", systemImage: "square.and.arrow.up")
                        }
                        .disabled(export.items.isEmpty)
                    }
                } footer: {
                    Text("Send it by iMessage, AirDrop or email. When they tap the file and choose Makin' Groceries, new items are added and anything you've already bought is marked bought. Nothing they have is removed, and nothing is added twice. They need the app installed.")
                }
            }
            .navigationTitle("Send to Family")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task(id: "\(onlyThisStore)\(onlyNeeded)\(myName)\(store.items.count)") {
                fileURL = store.exportFile(export)
            }
        }
        .presentationDetents([.medium])
    }
}

/// Shown when a list file is opened: what would change, and a button to merge it.
struct ImportListView: View {
    @Environment(GroceryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let incoming: IncomingList
    @State private var done: ImportSummary?

    private var preview: ImportSummary { store.mergeImport(incoming.export, apply: false) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    let p = done ?? preview
                    summaryRow("plus.circle", "\(p.added) new item\(p.added == 1 ? "" : "s")", done != nil ? "added" : nil)
                    summaryRow("checkmark.circle", "\(p.markedBought) already bought", nil)
                    summaryRow("equal.circle", "\(p.unchanged) you already have", nil)
                    if !p.newStores.isEmpty {
                        summaryRow("storefront", "New store\(p.newStores.count == 1 ? "" : "s"): \(p.newStores.joined(separator: ", "))", nil)
                    }
                } header: {
                    Text(incoming.export.from.map { "From \($0)" } ?? "A shared list")
                } footer: {
                    Text(done == nil ? "Nothing you have will be removed or changed, other than marking items bought." : "Done. You can close this.")
                }

                Section("Items") {
                    ForEach(incoming.export.items, id: \.id) { item in
                        HStack {
                            Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(item.isChecked ? .green : .secondary)
                            Text(item.name)
                            if item.quantity > 1 { Text("×\(item.quantity)").foregroundStyle(.secondary) }
                            Spacer()
                            if let shop = item.shopName { Text(shop).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
            }
            .navigationTitle("Shared List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(done == nil ? "Cancel" : "Close") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add to My List") { done = store.mergeImport(incoming.export) }
                        .disabled(done != nil)
                }
            }
        }
    }

    private func summaryRow(_ symbol: String, _ text: String, _ suffix: String?) -> some View {
        Label(text + (suffix.map { " \($0)" } ?? ""), systemImage: symbol)
    }
}
