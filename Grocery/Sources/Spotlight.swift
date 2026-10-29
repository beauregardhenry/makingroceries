import CoreSpotlight
import SwiftUI

/// Puts meals, list items and past purchases in Spotlight, so searching from the Home Screen finds them.
/// Everything stays in the phone's own search index.
enum SpotlightIndex {
    static let domain = "com.beauregardhenry.makingroceries"
    @MainActor private static var pending: Task<Void, Never>?

    /// Re-indexes a moment after the last change, so a burst of edits is indexed once.
    @MainActor
    static func update(from store: GroceryStore) {
        pending?.cancel()
        pending = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            let items = store.spotlightEntries().map { entry in
                let attributes = CSSearchableItemAttributeSet(contentType: .text)
                attributes.title = entry.title
                attributes.contentDescription = entry.detail
                attributes.keywords = entry.keywords
                return CSSearchableItem(uniqueIdentifier: entry.id, domainIdentifier: domain, attributeSet: attributes)
            }
            let index = CSSearchableIndex.default()
            try? await index.deleteSearchableItems(withDomainIdentifiers: [domain])
            try? await index.indexSearchableItems(items)
        }
    }
}
