import SwiftUI
import UIKit

/// Choose the icon on your home screen.
struct AppIconView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var current = UIApplication.shared.alternateIconName
    @State private var message: String?

    private struct Option: Identifiable {
        let id: String
        let name: String
        /// The name iOS wants; nil is the main icon.
        let iconName: String?
        let preview: String
    }

    private let options = [
        Option(id: "orange", name: "Orange", iconName: nil, preview: "IconPreview-Orange"),
        Option(id: "lime", name: "Lime", iconName: "AppIcon-Lime", preview: "IconPreview-Lime"),
        Option(id: "berry", name: "Berry", iconName: "AppIcon-Berry", preview: "IconPreview-Berry"),
        Option(id: "midnight", name: "Midnight", iconName: "AppIcon-Midnight", preview: "IconPreview-Midnight"),
    ]

    var body: some View {
        NavigationStack {
            List {
                ForEach(options) { option in
                    Button {
                        choose(option)
                    } label: {
                        HStack(spacing: 14) {
                            Image(option.preview)
                                .resizable()
                                .frame(width: 60, height: 60)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                            Text(option.name).foregroundStyle(.primary)
                            Spacer()
                            if option.iconName == current { Image(systemName: "checkmark").foregroundStyle(.tint) }
                        }
                    }
                }
                if let message {
                    Section { Text(message).font(.footnote).foregroundStyle(.secondary) }
                }
            }
            .navigationTitle("App Icon")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium])
    }

    private func choose(_ option: Option) {
        guard UIApplication.shared.supportsAlternateIcons else {
            message = "This device doesn't support changing the icon."
            return
        }
        UIApplication.shared.setAlternateIconName(option.iconName) { error in
            Task { @MainActor in
                if error == nil {
                    current = option.iconName
                    message = nil
                } else {
                    message = "Couldn't change the icon."
                }
            }
        }
    }
}
