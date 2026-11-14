import SwiftUI

extension NameColor {
    var color: Color {
        switch self {
        case .blue: .blue
        case .pink: .pink
        case .green: .green
        case .orange: .orange
        case .purple: .purple
        case .teal: .teal
        case .red: .red
        case .indigo: .indigo
        case .yellow: .yellow
        case .mint: .mint
        case .cyan: .cyan
        case .brown: .brown
        }
    }
}

/// A row of color swatches under a person's name; the ringed one is theirs.
struct NameColorPicker: View {
    let selected: NameColor
    let pick: (NameColor) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(NameColor.allCases) { option in
                    Button { pick(option) } label: {
                        Circle()
                            .fill(option.color)
                            .frame(width: 24, height: 24)
                            .overlay {
                                if option == selected {
                                    Circle().strokeBorder(Color.primary, lineWidth: 2).padding(-4)
                                }
                            }
                            .padding(4)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(option.title)
                    .accessibilityAddTraits(option == selected ? .isSelected : [])
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Color")
    }
}

/// A person's name with a dot in their color, for pickers and menus (which otherwise drop colors).
struct PersonLabel: View {
    let name: String
    let color: NameColor

    var body: some View {
        Label {
            Text(name)
        } icon: {
            Image(uiImage: Self.dot(color))
        }
    }

    private static func dot(_ color: NameColor) -> UIImage {
        let size = CGSize(width: 14, height: 14)
        return UIGraphicsImageRenderer(size: size).image { _ in
            UIColor(color.color).setFill()
            UIBezierPath(ovalIn: CGRect(origin: .zero, size: size)).fill()
        }
        .withRenderingMode(.alwaysOriginal)
    }
}
