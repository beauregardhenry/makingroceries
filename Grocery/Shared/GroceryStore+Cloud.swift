import Foundation

/// The part of iCloud sync that doesn't need iCloud: turning each saved list into bytes for the cloud,
/// and merging a copy from the cloud into this phone's lists. CloudSync (in the app) moves the bytes.
///
/// Each of the app's files is one cloud record. Merging is the same three-way merge used when the
/// widget or Siri changed a file: `base` is the copy both sides last agreed on, so each side's
/// additions, edits and deletions are kept. With no base (the first sync on a device) nothing is
/// deleted; the phone's lists and the cloud's are combined.
extension GroceryStore {
    /// The files that sync, in the order they're sent.
    static let cloudFileNames = Storage.fileNames

    /// This phone's copy of one file, as the cloud stores it.
    func cloudData(for name: String) -> Data? {
        switch name {
        case "grocery": encoded(items)
        case "shops": encoded(shops)
        case "favorites": encoded(favorites)
        case "meals": encoded(meals)
        case "history": encoded(history)
        case "recurring": encoded(recurring)
        case "plan": encoded(plan)
        case "stock": encoded(stock)
        case "spending": encoded(spending)
        case "goals": encoded(goals)
        case "people": encoded(people)
        case "customAisles": encoded(customAisles)
        case "registryPeople": encoded(registryPeople)
        default: nil
        }
    }

    /// Merges a copy of one file from the cloud into this phone's lists. Returns the merged bytes, which
    /// differ from `remote` when this phone had changes the cloud doesn't (so they need sending), or nil
    /// when the copy can't be read, say from a newer version of the app, in which case nothing changes.
    @discardableResult
    func applyCloudCopy(name: String, remote: Data, base: Data?) -> Data? {
        switch name {
        case "grocery": merge(\.items, remote, base)
        case "shops": merge(\.shops, remote, base)
        case "favorites": merge(\.favorites, remote, base)
        case "meals": merge(\.meals, remote, base)
        case "history": merge(\.history, remote, base)
        case "recurring": merge(\.recurring, remote, base)
        case "plan": merge(\.plan, remote, base)
        case "stock": merge(\.stock, remote, base)
        case "spending": merge(\.spending, remote, base)
        case "goals": merge(\.goals, remote, base)
        case "people": merge(\.people, remote, base)
        case "customAisles": merge(\.customAisles, remote, base)
        case "registryPeople": merge(\.registryPeople, remote, base)
        default: nil
        }
    }

    /// The files whose current contents differ from what the cloud last had, so they need sending.
    func cloudFilesChanged(since baseline: CloudBaseline) -> [String] {
        Self.cloudFileNames.filter { cloudData(for: $0) != baseline[$0] }
    }

    private func encoded<Element: Encodable>(_ list: [Element]) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try? encoder.encode(list)
    }

    private func merge<Element: Codable & Equatable & Identifiable>(
        _ keyPath: ReferenceWritableKeyPath<GroceryStore, [Element]>, _ remote: Data, _ base: Data?
    ) -> Data? {
        guard let theirs = try? JSONDecoder().decode([Element].self, from: remote) else { return nil }
        let baseList = base.flatMap { try? JSONDecoder().decode([Element].self, from: $0) } ?? []
        let merged = ListMerge.merge(base: baseList, ours: self[keyPath: keyPath], theirs: theirs)
        // Setting the list saves it to its file as usual, which the widget and Siri read.
        if merged != self[keyPath: keyPath] { self[keyPath: keyPath] = merged }
        return encoded(merged)
    }
}

/// For each file, the bytes this phone and the cloud last agreed on: the base of the next merge.
/// Saved beside the app's files so it survives relaunches.
struct CloudBaseline: Equatable {
    private var files: [String: Data] = [:]
    private let folder: URL?

    /// A baseline kept in `folder`, or only in memory when it's nil (for tests).
    init(folder: URL? = Storage.directory.appending(path: "CloudSync", directoryHint: .isDirectory)) {
        self.folder = folder
        guard let folder else { return }
        for name in GroceryStore.cloudFileNames {
            if let data = try? Data(contentsOf: folder.appending(path: "base-\(name).json")) { files[name] = data }
        }
    }

    subscript(name: String) -> Data? {
        get { files[name] }
        set {
            files[name] = newValue
            guard let folder else { return }
            let url = folder.appending(path: "base-\(name).json")
            if let newValue {
                try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try? newValue.write(to: url, options: .atomic)
            } else {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    /// Forgets everything, so the next sync combines instead of merging (used when sync is turned off).
    mutating func reset() {
        for name in GroceryStore.cloudFileNames { self[name] = nil }
    }

    static func == (a: CloudBaseline, b: CloudBaseline) -> Bool { a.files == b.files }
}
