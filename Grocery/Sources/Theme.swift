import SwiftUI

/// Background tint for the list screen. Grey is the system default, with no tint.
enum Theme: String, CaseIterable, Identifiable {
    case grey, sage, sky, blush, butter, lavender, custom

    var id: String { rawValue }
    var name: String { rawValue.capitalized }

    static let presets = allCases.filter { $0 != .custom }

    func tint(custom: Color) -> Color {
        switch self {
        case .custom: custom
        case .grey: .clear
        case .sage: .green
        case .sky: .blue
        case .blush: .pink
        case .butter: .yellow
        case .lavender: .purple
        }
    }

    /// Swatch shown in the picker; grey has no tint so it needs its own color.
    var swatch: Color { self == .grey ? Color(.systemGray3) : tint(custom: .clear).opacity(0.55) }
}

extension Color {
    init(hex: String) {
        let value = UInt64(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0x34C759
        self.init(red: Double((value >> 16) & 0xFF) / 255,
                  green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255)
    }

    var hex: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}

enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }
    var name: String { rawValue.capitalized }

    /// Nil follows the device setting.
    var scheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

struct ThemePicker: View {
    @Binding var selection: Theme
    @Binding var custom: Color
    @Binding var appearance: Appearance

    var body: some View {
        VStack(spacing: 16) {
            swatches
            Picker("Appearance", selection: $appearance) {
                ForEach(Appearance.allCases) { Text($0.name).tag($0) }
            }
            .pickerStyle(.segmented)
        }
        .padding()
        .frame(width: 340)
        .presentationCompactAdaptation(.popover)
    }

    private var swatches: some View {
        HStack(spacing: 14) {
            ForEach(Theme.presets) { theme in
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
            ColorPicker("Custom color", selection: $custom, supportsOpacity: false)
                .labelsHidden()
                .scaleEffect(1.25)
                .frame(width: 34, height: 34)
                .overlay {
                    if selection == .custom {
                        Circle().strokeBorder(.primary.opacity(0.6), lineWidth: 2).frame(width: 42, height: 42)
                    }
                }
                .accessibilityLabel("Custom color")
                .accessibilityAddTraits(selection == .custom ? .isSelected : [])
        }
    }
}
