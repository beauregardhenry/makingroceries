import PhotosUI
import SwiftUI
import VisionKit

/// Photograph a receipt and the prices fill in on your list and in your price history.
struct ReceiptView: View {
    @Environment(GroceryStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private struct Line: Identifiable {
        let id = UUID()
        var entry: ReceiptEntry
        var item: GroceryItem?
        var include: Bool
        /// False when the receipt line has extra words, so the match needs a look.
        var certain = true
    }

    @State private var shopID: UUID?
    @State private var lines: [Line] = []
    @State private var isWorking = false
    @State private var message: String?
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var showingCamera = false
    @State private var done: String?

    init(shopID: UUID?) {
        _shopID = State(initialValue: shopID)
    }

    private var matched: [Int] { lines.indices.filter { lines[$0].item != nil } }
    private var unmatched: [Int] { lines.indices.filter { lines[$0].item == nil } }
    private var selectedCount: Int { lines.filter(\.include).count }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Store", selection: $shopID) {
                        Text("Any Store").tag(UUID?.none)
                        ForEach(store.shops) { Text($0.name).tag(UUID?.some($0.id)) }
                    }
                    if VNDocumentCameraViewController.isSupported {
                        Button("Scan a Receipt", systemImage: "camera.viewfinder") { showingCamera = true }
                            .disabled(isWorking)
                    }
                    PhotosPicker(selection: $pickedPhoto, matching: .images) {
                        Label("Read a Photo of a Receipt", systemImage: "photo.on.rectangle")
                    }
                    .disabled(isWorking)
                } footer: {
                    Text("The receipt is read on your phone and never uploaded or saved. Prices go on matching items and into your price history for this store.")
                }

                if isWorking {
                    Section { HStack { ProgressView(); Text("Reading…").foregroundStyle(.secondary) } }
                } else if let message {
                    Section { Text(message).font(.footnote).foregroundStyle(.secondary) }
                }

                if !matched.isEmpty {
                    Section("On your list") {
                        ForEach(matched, id: \.self) { i in row(i) }
                    }
                }
                if !unmatched.isEmpty {
                    Section {
                        ForEach(unmatched, id: \.self) { i in row(i) }
                    } header: {
                        Text("Not on your list")
                    } footer: {
                        Text("Turn these on to remember their prices anyway.")
                    }
                }
                if let done {
                    Section { Label(done, systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                }
            }
            .navigationTitle("Scan Receipt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(selectedCount == 0 ? "Done" : "Save \(selectedCount)", action: save)
                        .disabled(done != nil)
                }
            }
            .onChange(of: pickedPhoto) { _, item in
                guard let item else { return }
                Task {
                    defer { pickedPhoto = nil }
                    guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
                        message = "Couldn't open that photo."
                        return
                    }
                    await read([image])
                }
            }
            .fullScreenCover(isPresented: $showingCamera) {
                DocumentScanner { images in
                    showingCamera = false
                    if !images.isEmpty { Task { await read(images) } }
                } onCancel: {
                    showingCamera = false
                }
                .ignoresSafeArea()
            }
        }
    }

    private func row(_ i: Int) -> some View {
        Toggle(isOn: $lines[i].include) {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(lines[i].item?.name ?? lines[i].entry.name)
                    Spacer()
                    Text(Price.format(lines[i].entry.unitPrice)).monospacedDigit()
                }
                if lines[i].item != nil {
                    Text("Receipt: \(lines[i].entry.name)" + (lines[i].entry.quantity > 1 ? " · \(lines[i].entry.quantity) at \(Price.format(lines[i].entry.unitPrice))" : ""))
                        .font(.caption).foregroundStyle(.secondary)
                    if !lines[i].certain {
                        Text("Check this one: the receipt says more than your list does")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
            }
        }
    }

    private func read(_ images: [UIImage]) async {
        message = nil
        done = nil
        isWorking = true
        defer { isWorking = false }
        var rows: [String] = []
        for image in images {
            let page = await Task.detached(priority: .userInitiated) { () -> [String]? in
                guard let cg = image.cgImage else { return nil }
                return try? RecipeOCR.rows(in: cg, orientation: CGImagePropertyOrientation(image.imageOrientation))
            }.value
            guard let page else {
                message = "Couldn't read that image."
                return
            }
            rows += page
        }
        let entries = ReceiptParser.parse(rows: rows)
        guard !entries.isEmpty else {
            message = "Couldn't find any items and prices. Try a flatter, well-lit photo of the whole receipt."
            lines = []
            return
        }
        let candidates = store.items.filter { shopID == nil || $0.shopID == shopID || $0.shopID == nil }
        lines = entries.map { entry in
            let item = ReceiptMatcher.bestMatch(for: entry, in: candidates)
            let certain = item.map { ReceiptMatcher.isExact(entry.name, $0.name) } ?? true
            return Line(entry: entry, item: item, include: item != nil && certain, certain: certain)
        }
        let known = lines.filter { $0.item != nil }.count
        let unsure = lines.filter { $0.item != nil && !$0.certain }.count
        message = "Found \(entries.count) items, \(known) on your list."
            + (unsure > 0 ? " \(unsure) need a look before you turn them on." : "")
    }

    private func save() {
        let chosen = lines.filter(\.include).map { (entry: $0.entry, item: $0.item) }
        if chosen.isEmpty { dismiss(); return }
        let n = store.applyReceipt(chosen, shopID: shopID)
        done = "Saved \(n) price\(n == 1 ? "" : "s")."
        Task {
            try? await Task.sleep(for: .seconds(1))
            dismiss()
        }
    }
}
