import SwiftUI

/// How the app looks. Grey and the colors sit on top of light mode; Dark is the whole dark look.
enum Theme: String, CaseIterable, Identifiable {
    case grey, sage, sky, blush, butter, lavender, dark, custom

    var id: String { rawValue }
    var name: String { rawValue.capitalized }

    /// The swatches shown in the picker; the custom color has its own well.
    static let presets = allCases.filter { $0 != .custom }

    /// Only Dark changes the look of the whole app; every other choice is light mode with a tint.
    var scheme: ColorScheme { self == .dark ? .dark : .light }

    func tint(custom: Color) -> Color {
        switch self {
        case .custom: custom
        case .grey, .dark: .clear
        case .sage: .green
        case .sky: .blue
        case .blush: .pink
        case .butter: .yellow
        case .lavender: .purple
        }
    }

    /// Swatch shown in the picker; grey and dark have no tint so they need their own colors.
    var swatch: Color {
        switch self {
        case .grey: Color(white: 0.82)
        case .dark: Color(white: 0.13)
        default: tint(custom: .clear).opacity(0.5)
        }
    }

    /// Earlier versions kept dark mode as a separate setting. Carry a "dark" choice over to the new
    /// Dark swatch, once.
    static func migrateLegacyAppearance() {
        let defaults = UserDefaults.standard
        guard let old = defaults.string(forKey: "appearance") else { return }
        if old == "dark" { defaults.set(Theme.dark.rawValue, forKey: "theme") }
        defaults.removeObject(forKey: "appearance")
    }
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

struct ThemePicker: View {
    @Binding var selection: Theme
    @Binding var custom: Color

    var body: some View {
        HStack(spacing: 10) {
            ForEach(Theme.presets) { theme in
                Button {
                    selection = theme
                } label: {
                    // Drawn as it looks on a light screen, so the colors read the same even when the
                    // picker itself is showing in dark mode.
                    Circle()
                        .fill(Color.white)
                        .overlay(Circle().fill(theme.swatch))
                        .environment(\.colorScheme, .light)
                        .frame(width: 32, height: 32)
                        .overlay {
                            if theme == .dark {
                                Image(systemName: "moon.fill").font(.footnote).foregroundStyle(.white.opacity(0.9))
                            }
                        }
                        .overlay {
                            if theme == selection {
                                Circle().strokeBorder(Color.accentColor, lineWidth: 3).padding(-4)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(theme.name)
                .accessibilityAddTraits(theme == selection ? .isSelected : [])
            }
            ColorPicker("Custom color", selection: $custom, supportsOpacity: false)
                .labelsHidden()
                .scaleEffect(1.2)
                .frame(width: 32, height: 32)
                .overlay {
                    if selection == .custom {
                        Circle().strokeBorder(Color.accentColor, lineWidth: 3).padding(-4)
                    }
                }
                .accessibilityLabel("Custom color")
                .accessibilityAddTraits(selection == .custom ? .isSelected : [])
        }
        .padding()
        .frame(width: 370)
        .presentationCompactAdaptation(.popover)
    }
}
