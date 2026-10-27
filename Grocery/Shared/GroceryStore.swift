import Foundation
import Observation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// The app's data: the list, stores, history and everything else, kept in memory and saved as JSON files.
/// The topics are split across GroceryStore+*.swift files.
@Observable
final class GroceryStore {
    var items: [GroceryItem] = [] {
        didSet { persist(\.items, "grocery", refreshesWidgets: true) }
    }

    var shops: [Shop] = [] {
        didSet { persist(\.shops, "shops", refreshesWidgets: true) }
    }

    var favorites: [Favorite] = [] {
        didSet { persist(\.favorites, "favorites") }
    }

    var meals: [Meal] = [] {
        didSet { persist(\.meals, "meals") }
    }

    var history: [PastItem] = [] {
        didSet { persist(\.history, "history") }
    }

    var recurring: [RecurringItem] = [] {
        didSet { persist(\.recurring, "recurring") }
    }

    var plan: [PlannedMeal] = [] {
        didSet { persist(\.plan, "plan") }
    }

    /// What's in your kitchen and when it should be used by.
    var stock: [StockEntry] = [] {
        didSet { persist(\.stock, "stock") }
    }

    var spending: [SpendRecord] = [] {
        didSet { persist(\.spending, "spending") }
    }

    /// Names of saved files that couldn't be read at launch. Each was copied into the Recovered folder
    /// before anything was saved over it. The list screen tells you once, then clears this.
    var loadProblems: [String] = []

    /// While loading, assignments update memory only; nothing is written back.
    @ObservationIgnored private var suppressWrites = false
    /// Each file's bytes as this copy last read or saved them, to notice when another process saved since.
    @ObservationIgnored private var lastSeen: [String: Data] = [:]

    private static let sampleItems = [
        GroceryItem(name: "Bananas", quantity: 6, aisle: .produce),
        GroceryItem(name: "Milk", aisle: .dairy),
        GroceryItem(name: "Sourdough", aisle: .bakery),
    ]

    init() {
        let historyWasMissing = load()
        if historyWasMissing {
            // First run with history: start from what's already on the list.
            history = items.map { PastItem(name: $0.name, aisle: $0.aisle, shopID: $0.shopID, price: $0.price) }
        }
        applyRecurring()
    }

    /// Picks up anything a widget, Siri, the share sheet or the watch saved since this copy last looked,
    /// merging it with this copy's own changes. Files that haven't changed aren't touched.
    func reload() {
        refresh(\.items, "grocery", refreshesWidgets: true)
        refresh(\.shops, "shops", refreshesWidgets: true)
        refresh(\.favorites, "favorites")
        refresh(\.meals, "meals")
        refresh(\.history, "history")
        refresh(\.recurring, "recurring")
        refresh(\.plan, "plan")
        refresh(\.stock, "stock")
        refresh(\.spending, "spending")
        applyRecurring()
    }

    /// Reads every file into memory without writing anything back. Returns whether history was missing.
    private func load() -> Bool {
        suppressWrites = true
        defer { suppressWrites = false }
        // Sample items only on a true first run. An unreadable list starts empty instead, so the sample
        // items can never be saved over a list that merely failed to load.
        items = value(of: readFile([GroceryItem].self, "grocery"), ifMissing: Self.sampleItems)
        shops = value(of: readFile([Shop].self, "shops"), ifMissing: Shop.defaultNames.map { Shop(name: $0) })
        favorites = value(of: readFile([Favorite].self, "favorites"), ifMissing: [])
        meals = value(of: readFile([Meal].self, "meals"), ifMissing: [])
        let historyFile = readFile([PastItem].self, "history")
        history = value(of: historyFile, ifMissing: [])
        recurring = value(of: readFile([RecurringItem].self, "recurring"), ifMissing: [])
        plan = value(of: readFile([PlannedMeal].self, "plan"), ifMissing: [])
        stock = value(of: readFile([StockEntry].self, "stock"), ifMissing: [])
        spending = value(of: readFile([SpendRecord].self, "spending"), ifMissing: [])
        if case .missing = historyFile { return true }
        return false
    }

    // MARK: Storage

    static func same(_ a: String, _ b: String) -> Bool {
        a.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(b.trimmingCharacters(in: .whitespaces)) == .orderedSame
    }

    func refreshWidgets() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    private enum FileState<Value> {
        case missing
        case loaded(Value)
        /// The file exists but couldn't be decoded. A copy was kept in the Recovered folder.
        case unreadable
    }

    private func value<Value>(of state: FileState<Value>, ifMissing fallback: Value) -> Value where Value: RangeReplaceableCollection {
        switch state {
        case .loaded(let value): value
        case .missing: fallback
        case .unreadable: Value()
        }
    }

    private func readFile<Element: Decodable>(_ type: [Element].Type, _ name: String) -> FileState<[Element]> {
        let url = Storage.url(name)
        var state = FileState<[Element]>.missing
        coordinate(reading: url) { url in
            guard FileManager.default.fileExists(atPath: url.path), let data = try? Data(contentsOf: url) else {
                lastSeen[name] = nil
                return
            }
            // Remember the bytes even when they don't decode: the copy is kept, and the next save may
            // replace the unreadable file instead of trying to merge with it.
            lastSeen[name] = data
            if let decoded = try? JSONDecoder().decode(type, from: data) {
                state = .loaded(decoded)
            } else {
                keepUnreadableCopy(of: data, name: name)
                state = .unreadable
            }
        }
        return state
    }

    /// Saves one list, first merging in whatever another process saved since this copy last looked.
    private func persist<Element: Codable & Equatable & Identifiable>(
        _ keyPath: ReferenceWritableKeyPath<GroceryStore, [Element]>, _ name: String, refreshesWidgets: Bool = false
    ) {
        guard !suppressWrites else { return }
        var merged: [Element]?
        coordinate(writing: Storage.url(name)) { url in
            let ours = self[keyPath: keyPath]
            var value = ours
            let disk = try? Data(contentsOf: url)
            if let disk, disk != lastSeen[name] {
                if let theirs = try? JSONDecoder().decode([Element].self, from: disk) {
                    let base = lastSeen[name].flatMap { try? JSONDecoder().decode([Element].self, from: $0) } ?? []
                    value = ListMerge.merge(base: base, ours: ours, theirs: theirs)
                    if value != ours { merged = value }
                } else {
                    keepUnreadableCopy(of: disk, name: name)
                }
            }
            guard let data = try? JSONEncoder().encode(value) else { return }
            if data != disk { try? data.write(to: url, options: .atomic) }
            lastSeen[name] = data
        }
        if let merged { setWithoutSaving(keyPath, merged) }
        if refreshesWidgets { refreshWidgets() }
    }

    /// Brings one list up to date with the file, if another process changed it.
    private func refresh<Element: Codable & Equatable & Identifiable>(
        _ keyPath: ReferenceWritableKeyPath<GroceryStore, [Element]>, _ name: String, refreshesWidgets: Bool = false
    ) {
        var update: (merged: [Element], theirs: [Element])?
        coordinate(reading: Storage.url(name)) { url in
            guard let disk = try? Data(contentsOf: url), disk != lastSeen[name] else { return }
            guard let theirs = try? JSONDecoder().decode([Element].self, from: disk) else {
                keepUnreadableCopy(of: disk, name: name)
                lastSeen[name] = disk
                return
            }
            let base = lastSeen[name].flatMap { try? JSONDecoder().decode([Element].self, from: $0) } ?? []
            update = (ListMerge.merge(base: base, ours: self[keyPath: keyPath], theirs: theirs), theirs)
            lastSeen[name] = disk
        }
        guard let update else { return }
        setWithoutSaving(keyPath, update.merged)
        // This copy had changes the file doesn't, so save the combined list.
        if update.merged != update.theirs { persist(keyPath, name, refreshesWidgets: refreshesWidgets) }
        else if refreshesWidgets { refreshWidgets() }
    }

    private func setWithoutSaving<Element>(_ keyPath: ReferenceWritableKeyPath<GroceryStore, [Element]>, _ value: [Element]) {
        let wasSuppressed = suppressWrites
        suppressWrites = true
        self[keyPath: keyPath] = value
        suppressWrites = wasSuppressed
    }

    /// Keeps a copy of a file that couldn't be read, so nothing in it is lost when the file is next saved.
    private func keepUnreadableCopy(of data: Data, name: String) {
        let folder = Storage.directory.appending(path: "Recovered", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let stamp = Date().formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false)
            .timeSeparator(.omitted).dateTimeSeparator(.standard))
        try? data.write(to: folder.appending(path: "\(name)-\(stamp).json"), options: .atomic)
        if !loadProblems.contains(name) { loadProblems.append(name) }
    }

    /// Other processes (the widget, Siri, the share sheet) read and write the same files, so reads
    /// and writes take turns through a file coordinator.
    private func coordinate(reading url: URL, _ body: (URL) -> Void) {
        var error: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &error, byAccessor: body)
        if error != nil { body(url) }
    }

    private func coordinate(writing url: URL, _ body: (URL) -> Void) {
        var error: NSError?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forMerging, error: &error, byAccessor: body)
        if error != nil { body(url) }
    }
}
