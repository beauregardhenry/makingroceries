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
    @State private var clothingSizeText: String
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
        _clothingSizeText = State(initialValue: item.clothingSize ?? "")
        _repeatDays = State(initialValue: repeatDays)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $draft.name).textInputAutocapitalization(.words)
                    Stepper("Quantity: \(draft.quantity)", value: $draft.quantity, in: 1...99)
                    if draft.list == .registry {
                        Picker("For", selection: $draft.giftForID) {
                            Text("Not assigned yet").tag(UUID?.none)
                            ForEach(store.registryPeople) { Text($0.name).tag(UUID?.some($0.id)) }
                        }
                        Picker("Occasion", selection: Binding(get: { draft.occasion ?? "" }, set: { draft.occasion = $0.isEmpty ? nil : $0 })) {
                            Text("None").tag("")
                            ForEach(RegistryOccasion.all, id: \.self) { Text($0).tag($0) }
                        }
                    } else if draft.list == .clothing {
                        Picker("For", selection: $draft.personID) {
                            Text("No one yet").tag(UUID?.none)
                            ForEach(store.people) { Text($0.name).tag(UUID?.some($0.id)) }
                        }
                        LabeledContent("Size") {
                            TextField("M, 8, 10 Kids, 32x30", text: $clothingSizeText)
                                .multilineTextAlignment(.trailing)
                                .textInputAutocapitalization(.never)
                        }
                    } else {
                        Picker("Category", selection: $draft.aisle) {
                            ForEach(Aisle.allCases) { Label($0.rawValue, systemImage: $0.symbol).tag($0) }
                        }
                        if !store.customAisles.isEmpty || draft.customAisleID != nil {
                            Picker("Aisle", selection: $draft.customAisleID) {
                                Text("None").tag(UUID?.none)
                                ForEach(store.customAisles) { Text($0.name).tag(UUID?.some($0.id)) }
                            }
                        }
                        Picker("Store", selection: $draft.shopID) {
                            Text(Shop.noStoreName).tag(UUID?.none)
                            ForEach(store.shops) { Text($0.name).tag(UUID?.some($0.id)) }
                        }
                        Toggle("For a trip", isOn: Binding(get: { draft.list == .travel }, set: { draft.list = $0 ? .travel : nil }))
                    }
                } footer: {
                    Text(draft.list == .registry
                         ? "Gifts stay off your other lists. Find them under Registry. Checking one off marks it bought, so no one buys it twice."
                         : draft.list == .clothing
                         ? "The size isn't shown on the list. Press and hold the item to see it, with the date it was added."
                         : "Trip items stay off your other lists. Find them under Travel.")
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

                if let trend = store.priceTrend(for: draft.name) {
                    Section("Price History") {
                        PriceHistoryChart(trend: trend)
                        PriceTrendSummary(trend: trend)
                    }
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
        if draft.list == .clothing {
            let old = store.items.first { $0.id == draft.id }
            let trimmed = clothingSizeText.trimmingCharacters(in: .whitespaces)
            let new = trimmed.isEmpty ? nil : trimmed
            if new != old?.clothingSize {
                draft.clothingSize = new
                draft.sizeDate = new == nil ? nil : Date()
                if let new { store.rememberSize(new, for: draft.personID, itemNamed: draft.name) }
            }
        }
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
