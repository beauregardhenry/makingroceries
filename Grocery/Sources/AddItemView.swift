import SwiftUI

struct AddItemView: View {
    @Environment(GroceryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var quantity = 1
    @State private var aisle: Aisle = .produce
    @State private var customAisleID: UUID?
    @State private var shopID: UUID?
    @State private var priceText = ""
    @State private var showingScanner = false
    @State private var lookupMessage: String?
    @State private var isLookingUp = false
    /// Clothing asks who it's for and its size, a gift who it is for and the occasion, each instead of an
    /// aisle and store. Travel is the "For a trip" switch.
    @State private var list: SeparateList?
    @State private var giftForID: UUID?
    @State private var occasion = ""
    @State private var personID: UUID?
    @State private var sizeText = ""

    init(shopID: UUID?, list: SeparateList? = nil) {
        _shopID = State(initialValue: shopID)
        _list = State(initialValue: list)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Item name", text: $name).textInputAutocapitalization(.words)
                Button("Scan Barcode", systemImage: "barcode.viewfinder") { showingScanner = true }
                if isLookingUp {
                    HStack { ProgressView(); Text("Looking up product…").foregroundStyle(.secondary) }
                } else if let lookupMessage {
                    Text(lookupMessage).font(.footnote).foregroundStyle(.secondary)
                }
                Stepper("Quantity: \(quantity)", value: $quantity, in: 1...99)
                TextField("Price (optional)", text: $priceText).keyboardType(.decimalPad)
                if list == .registry {
                    Picker("For", selection: $giftForID) {
                        Text("Not assigned yet").tag(UUID?.none)
                        ForEach(store.registryPeople) { Text($0.name).tag(UUID?.some($0.id)) }
                    }
                    Picker("Occasion", selection: $occasion) {
                        Text("None").tag("")
                        ForEach(RegistryOccasion.all, id: \.self) { Text($0).tag($0) }
                    }
                } else if list == .clothing {
                    Picker("For", selection: $personID) {
                        Text("No one yet").tag(UUID?.none)
                        ForEach(store.people) { Text($0.name).tag(UUID?.some($0.id)) }
                    }
                    LabeledContent("Size") {
                        TextField(store.lastSize(for: personID, itemNamed: name).map { "Last: \($0)" } ?? "M, 8, 10 Kids, 32x30",
                                  text: $sizeText)
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.never)
                    }
                } else {
                    Picker("Category", selection: $aisle) {
                        ForEach(Aisle.allCases) { Label($0.rawValue, systemImage: $0.symbol).tag($0) }
                    }
                    if !store.customAisles.isEmpty {
                        Picker("Aisle", selection: $customAisleID) {
                            Text("None").tag(UUID?.none)
                            ForEach(store.customAisles) { Text($0.name).tag(UUID?.some($0.id)) }
                        }
                    }
                    Picker("Store", selection: $shopID) {
                        Text(Shop.noStoreName).tag(UUID?.none)
                        ForEach(store.shops) { Text($0.name).tag(UUID?.some($0.id)) }
                    }
                    Toggle("For a trip", isOn: Binding(get: { list == .travel }, set: { list = $0 ? .travel : nil }))
                }
            }
            .navigationTitle("New Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        store.add(name: name, quantity: quantity, aisle: aisle, shopID: list == .clothing || list == .registry ? nil : shopID,
                                  price: Price.parse(priceText), list: list, personID: personID, clothingSize: sizeText,
                                  customAisleID: customAisleID, giftForID: giftForID, occasion: occasion)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .sheet(isPresented: $showingScanner) {
            ScanSheet { code in Task { await lookUp(code) } }
        }
    }

    private func lookUp(_ code: String) async {
        isLookingUp = true
        lookupMessage = nil
        defer { isLookingUp = false }
        do {
            if let product = try await ProductLookup.product(for: code) {
                let size = product.size.flatMap(SizeParser.parse)
                let warning = AvoidList.message(AvoidList.warnings(allergens: product.allergens, ingredients: product.ingredients,
                                                                    avoid: AvoidList.words))
                store.add(name: product.name, quantity: quantity, aisle: product.aisle ?? aisle, shopID: shopID,
                          price: Price.parse(priceText), sizeAmount: size?.amount, sizeUnit: size?.unit,
                          warning: warning, barcode: code, list: list, personID: personID,
                          customAisleID: customAisleID, giftForID: giftForID, occasion: occasion)
                if let warning {
                    // Don't hide a warning by closing the sheet.
                    lookupMessage = "Added \(product.name). Warning: \(warning)."
                    name = ""
                } else {
                    dismiss()
                }
            } else {
                lookupMessage = "No product found for \(code). Type the name instead."
            }
        } catch {
            lookupMessage = "Couldn't look up that barcode. Check your connection."
        }
    }
}
