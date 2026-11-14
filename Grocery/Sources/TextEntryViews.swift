import SwiftUI

extension View {
    /// A name field: the keyboard capitalizes each word, and when you press Return or leave the field, every word
    /// is given a capital letter, pasted or dictated text included. (Changing the text while typing would drop
    /// keystrokes, so it waits until you're done.)
    func titleCase(_ text: Binding<String>) -> some View {
        modifier(TitleCaseField(text: text))
    }
}

private struct TitleCaseField: ViewModifier {
    @Binding var text: String
    @FocusState private var focused: Bool

    private func fix() {
        let fixed = TitleCase.apply(text)
        if fixed != text { text = fixed }
    }

    func body(content: Content) -> some View {
        content
            .textInputAutocapitalization(.words)
            .focused($focused)
            .onSubmit(fix)
            .onChange(of: focused) { _, isFocused in if !isFocused { fix() } }
            .onDisappear(perform: fix)
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
