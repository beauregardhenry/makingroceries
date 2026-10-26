import SwiftUI

/// Turns "milk, 6 bananas, eggs x2" into items.
enum QuickAdd {
    struct Entry: Equatable {
        var name: String
        var quantity: Int
    }

    static func parse(_ text: String) -> [Entry] {
        text.split(whereSeparator: { ",;\n".contains($0) }).compactMap { part in
            var words = part.split(separator: " ").map(String.init)
            var quantity = 1

            // "6 bananas", "6x bananas"
            if words.count > 1, let n = Int(words[0].trimmingCharacters(in: CharacterSet(charactersIn: "x×X"))), (1...99).contains(n) {
                quantity = n
                words.removeFirst()
            // "bananas x6", "bananas ×6"
            } else if words.count > 1, let last = words.last, last.count > 1, "x×X".contains(last.first!),
                      let n = Int(last.dropFirst()), (1...99).contains(n) {
                quantity = n
                words.removeLast()
            }

            let name = words.joined(separator: " ").trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return nil }
            return Entry(name: name.prefix(1).uppercased() + name.dropFirst(), quantity: quantity)
        }
    }
}

/// Type several items at once, with suggestions from items you've added before.
struct QuickAddBar: View {
    @Environment(GroceryStore.self) private var store
    /// The store new items go to; nil leaves it to history.
    let shopID: UUID?
    let inferShop: Bool
    @State private var text = ""
    @FocusState private var focused: Bool

    private var token: String {
        text.split(separator: ",", omittingEmptySubsequences: false).last
            .map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
    }

    /// Everything typed before the last comma, kept when a suggestion replaces the last word.
    private var typedBefore: String {
        guard let comma = text.lastIndex(of: ",") else { return "" }
        return String(text[...comma]) + " "
    }

    private var canAdd: Bool { !QuickAdd.parse(text).isEmpty }

    var body: some View {
        VStack(spacing: 8) {
            let suggestions = store.suggestions(for: token)
            if !suggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(suggestions) { past in
                            Button {
                                text = typedBefore + past.name + ", "
                                focused = true
                            } label: {
                                Label(past.name, systemImage: past.aisle.symbol)
                                    .font(.subheadline)
                                    .padding(.horizontal, 12).padding(.vertical, 7)
                                    .background(.fill.tertiary, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                TextField("Add items: milk, eggs, 6 bananas", text: $text)
                    .focused($focused)
                    .submitLabel(.done)
                    .textInputAutocapitalization(.sentences)
                    .onSubmit(submit)
                Button(action: submit) {
                    Image(systemName: "arrow.up.circle.fill").font(.title2)
                }
                .disabled(!canAdd)
                .accessibilityLabel("Add items")
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule())
        }
    }

    private func submit() {
        let entries = QuickAdd.parse(text)
        guard !entries.isEmpty else { return }
        withAnimation {
            for entry in entries {
                store.addOrBump(name: entry.name, quantity: entry.quantity, shopID: shopID, inferShop: inferShop)
            }
        }
        text = ""
        focused = true
    }
}
