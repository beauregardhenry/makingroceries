import SwiftUI

/// Settings › Allergies & Avoid List: foods to avoid, grouped by category and alphabetized, each with what it
/// does to you. Synced with iCloud and shared with family on a shared list.
struct AvoidListView: View {
    @Environment(GroceryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var newWord = ""
    @State private var reactionsFor: Allergy?

    private func add(_ word: String) {
        if store.addAllergy(named: word) != nil { newWord = "" }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("Add something to avoid", text: $newWord).titleCase($newWord)
                            .submitLabel(.done)
                            .onSubmit { add(newWord) }
                        Button("Add") { add(newWord) }.disabled(newWord.trimmingCharacters(in: .whitespaces).count < 3)
                    }
                    let offered = AllergenSuggestions.matches(for: newWord, excluding: store.allergies.map(\.name))
                    if !offered.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(offered, id: \.self) { suggestion in
                                    Button(suggestion) { add(suggestion) }
                                        .buttonStyle(.bordered).controlSize(.small)
                                }
                            }
                        }
                    }
                } footer: {
                    Text("Start typing for suggestions. When you scan or look up a product, the app checks its allergens and ingredients and flags the item if it contains any of these.")
                }

                ForEach(store.allergyGroups, id: \.category) { group in
                    Section {
                        ForEach(group.allergies) { allergy in
                            row(allergy)
                        }
                    } header: {
                        Label(group.category.rawValue, systemImage: group.category.symbol)
                    }
                }

                if !store.allergies.isEmpty {
                    Section {
                        Text("Press and hold an allergy to note what it does to you, move it to another category, or delete it.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }

                Section {
                    Label("The data comes from Open Food Facts, a community database, and can be missing or wrong. Always read the label if you have an allergy.", systemImage: "exclamationmark.triangle")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Allergies & Avoid List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(item: $reactionsFor) { allergy in
                ReactionPicker(allergyID: allergy.id)
            }
        }
    }

    private func row(_ allergy: Allergy) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(allergy.name)
            let reactions = allergy.reactionList
            if !reactions.isEmpty {
                Text(reactions.map(\.rawValue).joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(reactions.contains(where: \.isSevere) ? Color.red : Color.secondary)
            }
        }
        .accessibilityIdentifier("allergy-\(allergy.name)")
        .contextMenu {
            Button("What It Does to You…", systemImage: "heart.text.square") { reactionsFor = allergy }
            Menu("Category", systemImage: "folder") {
                ForEach(AllergyCategory.allCases) { category in
                    Button {
                        store.setCategory(category, for: allergy.id)
                    } label: {
                        if category == allergy.category {
                            Label(category.rawValue, systemImage: "checkmark")
                        } else {
                            Text(category.rawValue)
                        }
                    }
                }
            }
            Button("Delete", systemImage: "trash", role: .destructive) { store.deleteAllergy(allergy.id) }
        }
    }
}

/// Pick any number of reactions for one allergy.
private struct ReactionPicker: View {
    @Environment(GroceryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let allergyID: UUID

    private var allergy: Allergy? { store.allergies.first { $0.id == allergyID } }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(AllergyReaction.allCases) { reaction in
                        let picked = allergy?.reactionList.contains(reaction) ?? false
                        Button {
                            store.toggleReaction(reaction, for: allergyID)
                        } label: {
                            HStack {
                                Label(reaction.rawValue, systemImage: reaction.symbol)
                                    .foregroundStyle(reaction.isSevere ? Color.red : Color.primary)
                                Spacer()
                                if picked { Image(systemName: "checkmark").foregroundStyle(Color.accentColor).bold() }
                            }
                        }
                        .accessibilityAddTraits(picked ? .isSelected : [])
                    }
                } footer: {
                    Text("Pick everything it does. Anaphylaxis and trouble breathing are called out when a scanned product contains it.")
                }
            }
            .navigationTitle(allergy?.name ?? "Reactions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}
