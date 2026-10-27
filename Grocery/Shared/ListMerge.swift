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
        return result
    }
}
