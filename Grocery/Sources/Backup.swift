import SwiftUI
import UniformTypeIdentifiers

/// Save everything to a file you can keep, and load it back.
struct BackupView: View {
    @Environment(GroceryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var fileURL: URL?
    @State private var importing = false
    @State private var pending: Backup?
    @State private var message: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if let fileURL {
                        ShareLink(item: fileURL) {
                            Label("Export Backup", systemImage: "square.and.arrow.up")
                        }
                    }
                } footer: {
                    Text("Saves your list, stores, aisle maps, usual items, meals and history to one file. Send it to Files, iCloud Drive or email. Item photos aren't included.")
                }

                Section {
                    Button("Restore from Backup…", systemImage: "arrow.down.doc") { importing = true }
                } footer: {
                    Text("Restoring replaces what's in the app now.")
                }

                if let message {
                    Section { Text(message).font(.footnote).foregroundStyle(.secondary) }
                }
            }
            .navigationTitle("Back Up & Restore")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { fileURL = writeBackup() }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                switch result {
                case .success(let url):
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    if let data = try? Data(contentsOf: url), let backup = try? JSONDecoder().decode(Backup.self, from: data) {
                        pending = backup
                    } else {
                        message = "That file isn't a Makin' Groceries backup."
                    }
                case .failure:
                    message = "Couldn't open that file."
                }
            }
            .alert("Replace Everything?", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
                   presenting: pending) { backup in
                Button("Replace", role: .destructive) {
                    store.restore(backup)
                    message = "Restored \(backup.items.count) items and \(backup.shops.count) stores."
                    fileURL = writeBackup()
                }
                Button("Cancel", role: .cancel) {}
            } message: { backup in
                Text("This backup has \(backup.items.count) items, \(backup.shops.count) stores and \(backup.meals.count) meals. What's in the app now will be replaced.")
            }
        }
        .presentationDetents([.medium])
    }

    private func writeBackup() -> URL? {
        let stamp = Date().formatted(.iso8601.year().month().day())
        let url = FileManager.default.temporaryDirectory.appending(path: "MakinGroceries-\(stamp).json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .deferredToDate
        guard let data = try? encoder.encode(store.makeBackup()), (try? data.write(to: url, options: .atomic)) != nil else { return nil }
        return url
    }
}
