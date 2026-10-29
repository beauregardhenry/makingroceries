import SwiftUI

/// Type several items at once, with suggestions from items you've added before.
struct QuickAddBar: View {
    @Environment(GroceryStore.self) private var store
    /// The store new items go to; nil leaves it to history.
    let shopID: UUID?
    let inferShop: Bool
    /// Bumped by the list screen when a control asks to add items; the field then takes focus.
    var focusRequest = 0
    /// Typed into the field along with a focus request, when not empty.
    var prefill = ""
    @State private var text = ""
    @State private var dictation = Dictation()
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
            let due = text.isEmpty ? store.dueItems() : []
            if !due.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Text("Due").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        ForEach(due) { past in
                            Button {
                                withAnimation { store.addOrBump(name: past.name, shopID: shopID, inferShop: inferShop) }
                            } label: {
                                Label(past.name, systemImage: "clock.arrow.circlepath")
                                    .font(.subheadline)
                                    .padding(.horizontal, 12).padding(.vertical, 7)
                                    .background(.fill.tertiary, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("You usually buy this about now. Adds it to the list.")
                        }
                    }
                }
            }

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

            if let message = dictation.message {
                Text(message).font(.caption).foregroundStyle(.orange).frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 8) {
                TextField("Add items: milk, eggs, 6 bananas", text: $text)
                    .accessibilityIdentifier("quickAddField")
                    .focused($focused)
                    .submitLabel(.done)
                    .textInputAutocapitalization(.sentences)
                    .onSubmit(submit)
                Button {
                    Task { await dictation.toggle() }
                } label: {
                    Image(systemName: dictation.isListening ? "mic.fill" : "mic")
                        .font(.title3)
                        .foregroundStyle(dictation.isListening ? Color.red : Color.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(dictation.isListening ? "Stop dictation" : "Dictate items")
                Button(action: submit) {
                    Image(systemName: "arrow.up.circle.fill").font(.title2)
                }
                .disabled(!canAdd)
                .accessibilityLabel("Add items")
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule())
            .onChange(of: dictation.transcript) { _, spoken in
                if dictation.isListening { text = spoken }
            }
            .onChange(of: dictation.isListening) { _, listening in
                if !listening, !dictation.transcript.isEmpty {
                    text = QuickAdd.written(fromSpoken: dictation.transcript)
                    dictation.transcript = ""
                }
            }
        }
        .onChange(of: focusRequest) { _, _ in
            if !prefill.isEmpty { text = prefill }
            focused = true
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
