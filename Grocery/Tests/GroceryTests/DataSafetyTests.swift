import XCTest

private struct Entry: Identifiable, Equatable {
    var id: Int
    var value: String
}

final class ListMergeTests: XCTestCase {
    private let base = [Entry(id: 1, value: "a"), Entry(id: 2, value: "b"), Entry(id: 3, value: "c")]

    func testWhenOnlyOneSideChangedThatSideIsKeptExactly() {
        let reordered = [base[2], base[0], base[1]]
        XCTAssertEqual(ListMerge.merge(base: base, ours: reordered, theirs: base), reordered)
        XCTAssertEqual(ListMerge.merge(base: base, ours: base, theirs: reordered), reordered)
    }

    func testAdditionsFromBothSidesAreKept() {
        let ours = base + [Entry(id: 4, value: "ours")]
        let theirs = base + [Entry(id: 5, value: "theirs")]
        XCTAssertEqual(ListMerge.merge(base: base, ours: ours, theirs: theirs).map(\.id), [1, 2, 3, 5, 4])
    }

    func testDeletionsApplyUnlessTheOtherSideEditedTheEntry() {
        let ours = [base[0], base[2]]                                        // we deleted 2
        XCTAssertEqual(ListMerge.merge(base: base, ours: ours, theirs: base + [Entry(id: 9, value: "x")]).map(\.id), [1, 3, 9])
        let theyEdited = [base[0], Entry(id: 2, value: "edited"), base[2], Entry(id: 9, value: "x")]
        XCTAssertEqual(ListMerge.merge(base: base, ours: ours, theirs: theyEdited).map(\.value), ["a", "edited", "c", "x"])
    }

    func testTheirDeletionLosesToOurEdit() {
        let ours = [base[0], Entry(id: 2, value: "mine"), base[2]]
        let theirs = [base[0], base[2]]                                      // they deleted 2
        XCTAssertEqual(ListMerge.merge(base: base, ours: ours, theirs: theirs).map(\.value), ["a", "c", "mine"])
        XCTAssertEqual(ListMerge.merge(base: base, ours: base + [Entry(id: 4, value: "d")], theirs: theirs).map(\.id), [1, 3, 4])
    }

    func testWhenBothEditTheSameEntryOursWins() {
        let ours = [base[0], Entry(id: 2, value: "ours"), base[2]]
        let theirs = [base[0], Entry(id: 2, value: "theirs"), base[2], Entry(id: 4, value: "d")]
        XCTAssertEqual(ListMerge.merge(base: base, ours: ours, theirs: theirs).map(\.value), ["a", "ours", "c", "d"])
    }

    func testTheSameNewEntryOnBothSidesAppearsOnce() {
        let ours = base + [Entry(id: 4, value: "ours")]
        let theirs = base + [Entry(id: 4, value: "theirs"), Entry(id: 5, value: "e")]
        XCTAssertEqual(ListMerge.merge(base: base, ours: ours, theirs: theirs).map(\.value), ["a", "b", "c", "ours", "e"])
    }
}

/// A file that can't be read must never be replaced by sample data or an empty list without a copy.
final class UnreadableFileTests: StoreTestCase {
    private func corrupt(_ name: String) throws {
        try Data("{ this is not a grocery list".utf8).write(to: Storage.url(name))
    }

    private func recoveredCopies() -> [URL] {
        let folder = Storage.directory.appending(path: "Recovered")
        return (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
    }

    func testAnUnreadableListStartsEmptyAndKeepsACopy() throws {
        store.add(name: "Milk", quantity: 1, aisle: .dairy)
        try corrupt("grocery")
        let reopened = GroceryStore()
        XCTAssertTrue(reopened.items.isEmpty, "never the sample items: \(reopened.items.map(\.name))")
        XCTAssertEqual(reopened.loadProblems, ["grocery"])
        let copy = try XCTUnwrap(recoveredCopies().first { $0.lastPathComponent.hasPrefix("grocery-") })
        XCTAssertEqual(try Data(contentsOf: copy), Data("{ this is not a grocery list".utf8))

        reopened.add(name: "Eggs", quantity: 1, aisle: .dairy)
        XCTAssertEqual(decodedItems().map(\.name), ["Eggs"])
        XCTAssertEqual(try Data(contentsOf: copy), Data("{ this is not a grocery list".utf8), "the copy survives the next save")
    }

    func testUnreadableHistoryIsNotRebuiltOverTheOriginal() throws {
        store.add(name: "Milk", quantity: 1, aisle: .dairy)
        try corrupt("history")
        let reopened = GroceryStore()
        XCTAssertTrue(reopened.history.isEmpty)
        XCTAssertEqual(reopened.loadProblems, ["history"])
        XCTAssertEqual(reopened.items.map(\.name), ["Milk"])
    }

    func testOnlyATrueFirstRunGetsTheSampleItems() throws {
        // The shared setup saved an empty list; a first run has no file at all.
        try FileManager.default.removeItem(at: Storage.url("grocery"))
        let fresh = GroceryStore()
        XCTAssertEqual(fresh.items.map(\.name), ["Bananas", "Milk", "Sourdough"])
        XCTAssertTrue(fresh.loadProblems.isEmpty)
        XCTAssertNil(savedData("grocery"), "loading alone writes nothing")
    }

    func testLoadingNeverRewritesFiles() throws {
        store.add(name: "Milk", quantity: 1, aisle: .dairy)
        _ = store.addShop(named: "Kroger")
        let before = Storage.fileNames.map { (savedData($0), modificationDate($0)) }
        _ = GroceryStore()
        _ = GroceryStore()
        let after = Storage.fileNames.map { (savedData($0), modificationDate($0)) }
        for (name, (old, new)) in zip(Storage.fileNames, zip(before, after)) {
            XCTAssertEqual(old.0, new.0, "\(name) contents changed")
            XCTAssertEqual(old.1, new.1, "\(name) was rewritten")
        }
    }
}

/// The app keeps the list in memory while the widget, Siri and the share sheet change the same files.
final class ConcurrentChangeTests: StoreTestCase {
    func testChangesFromAnotherProcessAreMergedOnSave() throws {
        store.add(name: "Milk", quantity: 1, aisle: .dairy)
        let widget = GroceryStore()                     // another process with its own copy
        widget.toggle(widget.items[0])
        widget.add(name: "Eggs", quantity: 1, aisle: .dairy)

        store.add(name: "Rice", quantity: 1, aisle: .pantry)   // the app, still holding the old list

        let saved = decodedItems()
        XCTAssertEqual(Set(saved.map(\.name)), ["Milk", "Eggs", "Rice"])
        XCTAssertTrue(try XCTUnwrap(saved.first { $0.name == "Milk" }).isChecked, "the widget's check-off survived")
        XCTAssertEqual(Set(store.items.map(\.name)), ["Milk", "Eggs", "Rice"], "the app's copy now matches")
    }

    func testADeletionElsewhereAndAnEditHereBothSurvive() throws {
        store.add(name: "Milk", quantity: 1, aisle: .dairy)
        store.add(name: "Bread", quantity: 1, aisle: .bakery)
        let widget = GroceryStore()
        widget.delete(widget.items.first { $0.name == "Milk" }!)

        let bread = try XCTUnwrap(store.items.first { $0.name == "Bread" })
        var edited = bread
        edited.quantity = 3
        store.update(edited)

        let saved = decodedItems()
        XCTAssertEqual(saved.map(\.name), ["Bread"])
        XCTAssertEqual(saved.first?.quantity, 3)
    }

    func testReloadPicksUpOtherChangesWithoutRewritingUntouchedFiles() throws {
        store.add(name: "Milk", quantity: 1, aisle: .dairy)
        _ = store.addShop(named: "Kroger")
        let shopsWritten = modificationDate("shops")

        let siri = GroceryStore()
        siri.addOrBump(name: "Coffee", shopID: nil)

        store.reload()
        XCTAssertTrue(store.items.contains { $0.name == "Coffee" })
        XCTAssertEqual(modificationDate("shops"), shopsWritten)
    }

    func testReloadWithNoOutsideChangesWritesNothing() {
        store.add(name: "Milk", quantity: 1, aisle: .dairy)
        let before = Storage.fileNames.map(modificationDate)
        store.reload()
        XCTAssertEqual(Storage.fileNames.map(modificationDate), before)
    }

    func testUnsavedLocalChangesSurviveAReload() {
        store.add(name: "Milk", quantity: 1, aisle: .dairy)
        let widget = GroceryStore()
        widget.add(name: "Eggs", quantity: 1, aisle: .dairy)
        store.reload()
        store.add(name: "Rice", quantity: 1, aisle: .pantry)
        XCTAssertEqual(Set(decodedItems().map(\.name)), ["Milk", "Eggs", "Rice"])
    }
}
