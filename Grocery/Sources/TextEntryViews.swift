import SwiftUI

extension View {
    /// A name field: each word starts with a capital letter as you type, pasted or dictated text included.
    func titleCase(_ text: Binding<String>) -> some View {
        textInputAutocapitalization(.words)
            .onChange(of: text.wrappedValue) { _, typed in
                let fixed = TitleCase.apply(typed)
                if fixed != typed { text.wrappedValue = fixed }
            }
    }
}

/// "Did you mean…?" under a name field, when what's typed looks misspelled. Tapping it uses the suggestion.
struct SpellingSuggestion: View {
    let suggestion: String
    let apply: () -> Void

    var body: some View {
        Button(action: apply) {
            Label {
                Text("Did you mean ") + Text(suggestion).bold() + Text("?")
            } icon: {
                Image(systemName: "text.badge.checkmark")
            }
            .font(.subheadline)
        }
        .accessibilityIdentifier("spellingSuggestion")
    }
}
