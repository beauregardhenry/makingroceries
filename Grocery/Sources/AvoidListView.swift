import SwiftUI

struct AvoidListView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var words = AvoidList.words
    @State private var newWord = ""

    private static let suggestions = ["Peanuts", "Tree nuts", "Milk", "Eggs", "Gluten", "Soy", "Shellfish", "Fish", "Sesame"]

    private func add(_ word: String) {
        let trimmed = word.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 3, !words.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return }
        words.append(trimmed)
        newWord = ""
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("Add something to avoid", text: $newWord)
                            .submitLabel(.done)
                            .onSubmit { add(newWord) }
                        Button("Add") { add(newWord) }.disabled(newWord.trimmingCharacters(in: .whitespaces).count < 3)
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(Self.suggestions.filter { s in !words.contains { $0.caseInsensitiveCompare(s) == .orderedSame } }, id: \.self) { s in
                                Button(s) { add(s) }
                                    .buttonStyle(.bordered).controlSize(.small)
                            }
                        }
                    }
                } footer: {
                    Text("When you scan or look up a product, the app checks its allergens and ingredients and flags the item if it contains any of these.")
                }

                if !words.isEmpty {
                    Section("Avoiding") {
                        ForEach(words, id: \.self) { Text($0) }
                            .onDelete { words.remove(atOffsets: $0) }
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
            .onChange(of: words) { _, new in AvoidList.words = new }
        }
    }
}
