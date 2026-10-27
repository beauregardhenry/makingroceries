import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// What the Share sheet handed us: a web page address, some selected text, or nothing usable.
enum SharedInput {
    case url(URL)
    case text(String)
    case none
}

/// Appears in Safari's Share sheet as "Makin' Groceries". Reads the recipe on the page and
/// saves it as a meal or adds it to the list.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let root = ShareView(
            readInput: { [weak self] in await self?.readInput() ?? .none },
            close: { [weak self] in self?.extensionContext?.completeRequest(returningItems: nil) }
        )
        let host = UIHostingController(rootView: root)
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }

    private func readInput() async -> SharedInput {
        let items = extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
        let providers = items.flatMap { $0.attachments ?? [] }
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            if let value = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier), let url = value as? URL {
                return .url(url)
            }
        }
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            if let value = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier), let text = value as? String {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.contains("\n"), let url = RecipeFetcher.normalized(trimmed), trimmed.contains(".") { return .url(url) }
                return .text(text)
            }
        }
        return .none
    }
}
