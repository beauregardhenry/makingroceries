import SwiftUI

/// Background tint for the list screen. Grey is the system default, with no tint.
enum Theme: String, CaseIterable, Identifiable {
    case grey, sage, sky, blush, butter, lavender

    var id: String { rawValue }
    var name: String { rawValue.capitalized }

    var tint: Color {
        switch self {
        case .grey: .clear
        case .sage: .green
        case .sky: .blue
        case .blush: .pink
        case .butter: .yellow
        case .lavender: .purple
        }
    }

    /// Swatch shown in the picker; grey has no tint so it needs its own color.
    var swatch: Color { self == .grey ? Color(.systemGray3) : tint.opacity(0.55) }
}

struct ThemePicker: View {
    @Binding var selection: Theme

    var body: some View {
        HStack(spacing: 14) {
            ForEach(Theme.allCases) { theme in
                Button {
                    selection = theme
                } label: {
                    Circle()
                        .fill(theme.swatch)
                        .frame(width: 34, height: 34)
                        .overlay {
                            if theme == selection {
                                Image(systemName: "checkmark").font(.footnote.bold()).foregroundStyle(.white)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(theme.name)
                .accessibilityAddTraits(theme == selection ? .isSelected : [])
            }
        }
        .padding()
        .presentationCompactAdaptation(.popover)
    }
}
