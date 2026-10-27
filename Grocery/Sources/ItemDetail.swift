import SwiftUI
import PhotosUI

/// Everything about one item on the list: name, quantity, aisle, store, price, note, photo, repeat.
struct ItemDetailView: View {
    @Environment(GroceryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var draft: GroceryItem
    @State private var priceText: String
    @State private var noteText: String
    @State private var sizeText: String
    @State private var repeatDays: Int
    @State private var pickedPhoto: PhotosPickerItem?
    /// Photos saved during this edit, so unused ones can be deleted afterwards.
    @State private var newPhotos: [String] = []

    private static let repeatOptions = [(0, "Never"), (7, "Every week"), (14, "Every 2 weeks"), (30, "Every month")]

    init(item: GroceryItem, repeatDays: Int) {
        _draft = State(initialValue: item)
        _priceText = State(initialValue: Price.editText(item.price))
        _noteText = State(initialValue: item.note ?? "")
        _sizeText = State(initialValue: item.sizeAmount.flatMap { a in item.sizeUnit.map { SizeParser.label(a, $0) } } ?? "")
        _repeatDays = State(initialValue: repeatDays)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $draft.name)
                    Stepper("Quantity: \(draft.quantity)", value: $draft.quantity, in: 1...99)
                    Picker("Aisle", selection: $draft.aisle) {
                        ForEach(Aisle.allCases) { Label($0.rawValue, systemImage: $0.symbol).tag($0) }
                    }
                    Picker("Store", selection: $draft.shopID) {
                        Text("Any Store").tag(UUID?.none)
                        ForEach(store.shops) { Text($0.name).tag(UUID?.some($0.id)) }
                    }
                }

                Section {
                    LabeledContent("Price of one") {
                        TextField("Optional", text: $priceText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Size") {
                        TextField("16 oz, 1 lb, 12 ct", text: $sizeText)
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.never)
                    }
                    LabeledContent("Note") {
                        TextField("Brand, size, coupon", text: $noteText, axis: .vertical)
                            .lineLimit(1...3)
                            .multilineTextAlignment(.trailing)
                    }
                } footer: {
                    let size = SizeParser.parse(sizeText)
                    let unit = UnitPrice.text(price: Price.parse(priceText), amount: size?.amount, unit: size?.unit)
                    Text((unit.map { "That's \($0). " } ?? "") + "Add a size to see the price per ounce, so different package sizes compare fairly. Notes show under the item, so a coupon or the exact brand is in front of you at the store.")
                }

                Section("Photo") {
                    if let photo = draft.photo {
                        HStack {
                            ItemThumbnail(name: photo, size: 72)
                            Spacer()
                            Button("Remove Photo", role: .destructive) { draft.photo = nil }
                                .buttonStyle(.borderless)
                        }
                    }
                    PhotosPicker(selection: $pickedPhoto, matching: .images) {
                        Label(draft.photo == nil ? "Add Photo" : "Change Photo", systemImage: "photo")
                    }
                }

                Section {
                    Picker("Repeat", selection: $repeatDays) {
                        ForEach(Self.repeatOptions, id: \.0) { Text($0.1).tag($0.0) }
                    }
                } footer: {
                    Text("A repeating item returns to your list by itself, if it isn't already there.")
                }
            }
            .navigationTitle("Item Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: cancel) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onChange(of: pickedPhoto) { _, picked in
                guard let picked else { return }
                Task {
                    if let data = try? await picked.loadTransferable(type: Data.self),
                       let name = PhotoStore.save(data) {
                        newPhotos.append(name)
                        draft.photo = name
                    }
                }
            }
        }
    }

    private func save() {
        draft.name = draft.name.trimmingCharacters(in: .whitespaces)
        draft.price = Price.parse(priceText)
        let note = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.note = note.isEmpty ? nil : note
        let size = SizeParser.parse(sizeText)
        draft.sizeAmount = size?.amount
        draft.sizeUnit = size?.unit
        store.update(draft)
        store.setRepeat(for: draft, everyDays: repeatDays == 0 ? nil : repeatDays)
        newPhotos.filter { $0 != draft.photo }.forEach(PhotoStore.remove)
        dismiss()
    }

    private func cancel() {
        newPhotos.forEach(PhotoStore.remove)
        dismiss()
    }
}
