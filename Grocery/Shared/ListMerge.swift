import Foundation

/// Combines two sets of changes to the same saved list, when the app and a widget, Siri or the share
/// sheet both changed it since they last read it.
enum ListMerge {
    /// A three-way merge by id. `base` is the list as it was last read or saved, `ours` is this copy's
    /// version, and `theirs` is what another process has saved since. Each side's additions, deletions
    /// and edits are kept. When both edited the same entry, ours wins, since it's the action just taken;
    /// an edit beats a deletion so nothing someone changed disappears. Order follows `theirs`, with our
    /// additions at the end, except when only one side changed anything, which keeps that side exactly.
    static func merge<Element: Identifiable & Equatable>(base: [Element], ours: [Element], theirs: [Element]) -> [Element] {
        if theirs == base { return ours }
        if ours == base { return theirs }

        let baseByID = Dictionary(base.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let oursByID = Dictionary(ours.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let theirIDs = Set(theirs.map(\.id))

        var result: [Element] = []
        var seen = Set<Element.ID>()

        for theirElement in theirs where seen.insert(theirElement.id).inserted {
            let id = theirElement.id
            switch (baseByID[id], oursByID[id]) {
            case let (base?, ours?):
                result.append(ours != base ? ours : theirElement)
            case let (base?, nil):
                // We deleted it. Keep it only if they changed it in the meantime.
                if theirElement != base { result.append(theirElement) }
            case let (nil, ours?):
                // Both added the same entry.
                result.append(ours)
            case (nil, nil):
                result.append(theirElement)
            }
        }

        for ourElement in ours where !seen.contains(ourElement.id) {
            let id = ourElement.id
            if let base = baseByID[id] {
                // They deleted it. Keep it only if we changed it.
                if !theirIDs.contains(id), ourElement != base {
                    result.append(ourElement)
                    seen.insert(id)
                }
            } else {
                result.append(ourElement)
                seen.insert(id)
            }
        }
        // Moving entries is a change too: if only we reordered (they just edited contents), keep our order.
        if reordered(ours, from: base), !reordered(theirs, from: base) {
            let position = Dictionary(ours.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
            let fallback = ours.count
            result = result.enumerated().sorted {
                let a = position[$0.element.id] ?? fallback + $0.offset, b = position[$1.element.id] ?? fallback + $1.offset
                return a < b
            }.map(\.element)
        }
        return result
    }

    /// Whether `list` puts the entries it shares with `base` in a different order.
    private static func reordered<Element: Identifiable>(_ list: [Element], from base: [Element]) -> Bool {
        let baseIDs = Set(base.map(\.id)), listIDs = Set(list.map(\.id))
        let mine = list.map(\.id).filter { baseIDs.contains($0) }
        let original = base.map(\.id).filter { listIDs.contains($0) }
        return mine != original
    }
}