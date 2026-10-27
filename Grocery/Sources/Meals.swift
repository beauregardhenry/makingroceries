import SwiftUI
import PhotosUI
import VisionKit

/// Batch sizes for adding a meal to the list.
enum BatchSize: Double, CaseIterable, Identifiable {
    case half = 0.5, one = 1, two = 2, three = 3, four = 4

    var id: Double { rawValue }
    var label: String { self == .half ? "½×" : "\(Int(rawValue))×" }
}

/// Saved meals: add every ingredient to the list in one tap, at any batch size.
struct MealsView: View {
    @Environment(GroceryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    /// The store currently selected, if any; nil lets history pick.
    let shopID: UUID?
    /// What's on screen now, so it can be saved as a meal.
    let currentItems: [GroceryItem]
    @State private var path: [UUID] = []
    @State private var showingImport = false

    private func newMeal(from items: [GroceryItem] = []) {
        let meal = Meal(name: "New meal", ingredients: items.map {
            MealIngredient(name: $0.name, quantity: $0.quantity, aisle: $0.aisle)
        })
        store.meals.append(meal)
        path.append(meal.id)
    }

    private func add(_ meal: Meal, scale: Double) {
        store.addToList(meal, shopID: shopID, scale: scale)
        dismiss()
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if store.meals.isEmpty {
                    Section {
                        Text("No meals yet. Tap + to create one, import a recipe, or save what's on your list now as a meal.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                ForEach(store.meals) { meal in
                    NavigationLink(value: meal.id) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(meal.name.isEmpty ? "Untitled meal" : meal.name)
                                Text("\(meal.ingredients.count) ingredient\(meal.ingredients.count == 1 ? "" : "s")")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Menu {
                                ForEach(BatchSize.allCases) { size in
                                    Button("Add \(size.label)") { add(meal, scale: size.rawValue) }
                                }
                            } label: {
                                Text("Add")
                                    .font(.subheadline.weight(.semibold))
                                    .padding(.horizontal, 14).padding(.vertical, 6)
                                    .background(Color.accentColor, in: Capsule())
                                    .foregroundStyle(.white)
                            } primaryAction: {
                                add(meal, scale: 1)
                            }
                            .disabled(meal.ingredients.isEmpty)
                            .accessibilityHint("Press and hold to add a half, double or bigger batch")
                        }
                    }
                }
                .onDelete { store.meals.remove(atOffsets: $0) }
            }
            .navigationTitle("Meals")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: UUID.self) { id in MealEditorView(mealID: id, shopID: shopID) }
            .sheet(isPresented: $showingImport) {
                RecipeImportView { id in path.append(id) }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("New Meal", systemImage: "plus") { newMeal() }
                        Button("Save Current List as Meal", systemImage: "square.and.arrow.down") {
                            newMeal(from: currentItems)
                        }
                        .disabled(currentItems.isEmpty)
                        Button("Import Recipe…", systemImage: "doc.text.magnifyingglass") { showingImport = true }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
    }
}

struct MealEditorView: View {
    @Environment(GroceryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let mealID: UUID
    let shopID: UUID?
    @State private var newText = ""
    @State private var batch: BatchSize = .one

    var body: some View {
        @Bindable var store = store
        if let i = store.meals.firstIndex(where: { $0.id == mealID }) {
            List {
                Section("Name") {
                    TextField("Meal name", text: $store.meals[i].name)
                }

                Section {
                    ForEach($store.meals[i].ingredients) { $ingredient in
                        HStack {
                            Image(systemName: ingredient.aisle.symbol).foregroundStyle(.secondary).frame(width: 24)
                            TextField("Ingredient", text: $ingredient.name)
                            if let amount = ingredient.amount, let unit = ingredient.unit {
                                Text(Amount.text(amount * batch.rawValue, unit: unit))
                                    .foregroundStyle(.secondary).monospacedDigit()
                            } else {
                                Stepper("Quantity \(ingredient.quantity)", value: $ingredient.quantity, in: 1...99)
                                    .labelsHidden()
                                Text("×\(ingredient.scaled(by: batch.rawValue).quantity)")
                                    .foregroundStyle(.secondary).monospacedDigit()
                                    .frame(minWidth: 30, alignment: .trailing)
                            }
                        }
                    }
                    .onDelete { store.meals[i].ingredients.remove(atOffsets: $0) }

                    HStack {
                        TextField("Add ingredients: rice, 2 chicken, broccoli", text: $newText)
                            .submitLabel(.done)
                            .onSubmit { addIngredients(to: i) }
                        Button("Add") { addIngredients(to: i) }
                            .disabled(RecipeParser.fromText(newText).isEmpty)
                    }
                } header: {
                    Text("Ingredients")
                }

                Section {
                    Picker("Batch size", selection: $batch) {
                        ForEach(BatchSize.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Button("Add All to List", systemImage: "cart.badge.plus") {
                        store.addToList(store.meals[i], shopID: shopID, scale: batch.rawValue)
                        dismiss()
                    }
                    .disabled(store.meals[i].ingredients.isEmpty)
                } header: {
                    Text("Add to list")
                } footer: {
                    Text("Counted items, like eggs, scale their quantity. Measured ones, like 2 cups of flour, stay one item with the scaled amount in its note.")
                }
            }
            .navigationTitle(store.meals[i].name.isEmpty ? "Meal" : store.meals[i].name)
            .navigationBarTitleDisplayMode(.inline)
        } else {
            ContentUnavailableView("Meal not found", systemImage: "fork.knife")
        }
    }

    private func addIngredients(to i: Int) {
        for line in RecipeParser.fromText(newText) {
            store.meals[i].ingredients.append(
                MealIngredient(name: line.name, quantity: line.quantity, aisle: store.resolveAisle(for: line.name),
                               amount: line.amount, unit: line.unit)
            )
        }
        newText = ""
    }
}

/// Turns a recipe web page, a photo of a recipe, or pasted ingredients into a meal.
struct RecipeImportView: View {
    @Environment(GroceryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let onCreated: (UUID) -> Void
    @State private var address = ""
    @State private var pasted = ""
    @State private var name = ""
    @State private var isWorking = false
    @State private var message: String?
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var showingCamera = false

    private var found: Int { RecipeParser.fromText(pasted).count }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://…", text: $address)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button {
                        Task { await fetch() }
                    } label: {
                        Text("Get Ingredients from Page")
                    }
                    .disabled(isWorking || address.trimmingCharacters(in: .whitespaces).isEmpty)
                } header: {
                    Text("Recipe web address")
                } footer: {
                    Text("Works with most recipe sites. Only the address you enter is contacted. From Safari, you can also use Share → Makin' Groceries.")
                }

                Section {
                    if VNDocumentCameraViewController.isSupported {
                        Button("Scan a Recipe with the Camera", systemImage: "camera.viewfinder") { showingCamera = true }
                            .disabled(isWorking)
                    }
                    PhotosPicker(selection: $pickedPhoto, matching: .images) {
                        Label("Read a Photo or Screenshot", systemImage: "photo.on.rectangle")
                    }
                    .disabled(isWorking)
                } header: {
                    Text("Photo of a recipe")
                } footer: {
                    Text("The text is read on your phone, and the photo is never uploaded or saved. Check the result below before creating the meal.")
                }

                if isWorking {
                    Section { HStack { ProgressView(); Text("Working…").foregroundStyle(.secondary) } }
                } else if let message {
                    Section { Text(message).font(.footnote).foregroundStyle(.secondary) }
                }

                Section {
                    TextEditor(text: $pasted).frame(minHeight: 160)
                } header: {
                    Text("Ingredients, one per line")
                } footer: {
                    Text(found == 0 ? "Paste a list, or fetch or scan one above." : "\(found) ingredient\(found == 1 ? "" : "s") found. Amounts like \"2 cups\" are kept, so you can scale the recipe.")
                }

                Section("Meal name") {
                    TextField("Name", text: $name)
                }
            }
            .navigationTitle("Import Recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create", action: create).disabled(found == 0)
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

    private func fetch() async {
        message = nil
        isWorking = true
        defer { isWorking = false }
        switch await RecipeFetcher.fetch(address: address) {
        case .found(let recipe):
            pasted = recipe.lines.joined(separator: "\n")
            if name.isEmpty, let title = recipe.name { name = title }
        case .noRecipe:
            message = "Couldn't find a recipe on that page. Copy the ingredients and paste them below instead."
        case .unreachable:
            message = "Couldn't reach that page. Check your connection."
        case .badAddress:
            message = "That doesn't look like a web address."
        }
    }

    /// Reads one or more photographed pages and puts the text in the editor for review.
    private func read(_ images: [UIImage]) async {
        message = nil
        isWorking = true
        defer { isWorking = false }
        var lines: [String] = []
        for image in images {
            let page = await Task.detached(priority: .userInitiated) { () -> [String]? in
                guard let cg = image.cgImage else { return nil }
                return try? RecipeOCR.lines(in: cg, orientation: CGImagePropertyOrientation(image.imageOrientation))
            }.value
            guard let page else {
                message = "Couldn't read that image."
                return
            }
            lines += page
        }
        let section = RecipeParser.ingredientSection(of: RecipeParser.joinWrappedLines(lines))
        guard !section.isEmpty else {
            message = "No text found. Try a sharper, well-lit photo."
            return
        }
        pasted = section.joined(separator: "\n")
        if name.isEmpty, let title = lines.first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }),
           RecipeParser.clean(line: title)?.unit == nil, title.count < 60, lines.count > section.count {
            name = title
        }
        message = found == 0 ? "Read the page, but didn't find any ingredients. Edit the text below." : nil
    }

    private func create() {
        let meal = store.makeMeal(named: name, fromLines: pasted)
        store.meals.append(meal)
        dismiss()
        onCreated(meal.id)
    }
}

extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}

/// Apple's document camera: finds the page, flattens it, and hands back the pictures.
struct DocumentScanner: UIViewControllerRepresentable {
    let onScan: ([UIImage]) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let parent: DocumentScanner
        init(_ parent: DocumentScanner) { self.parent = parent }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            parent.onScan((0..<scan.pageCount).map { scan.imageOfPage(at: $0) })
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) { parent.onCancel() }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) { parent.onCancel() }
    }
}
