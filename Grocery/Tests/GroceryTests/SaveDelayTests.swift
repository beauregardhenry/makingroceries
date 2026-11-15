import XCTest

final class SaveDelayTests: StoreTestCase {
    override func tearDown() {
        store.saveDelay = 0
        super.tearDown()
    }

    func testWithoutAPauseChangesAreWrittenAtOnce() {
        store.add(name: "Milk", quantity: 1, aisle: .dairy)
        XCTAssertFalse(store.hasPendingChanges)
        XCTAssertTrue(String(decoding: savedData("grocery") ?? Data(), as: UTF8.self).contains("Milk"))
    }

    func testTypingIsWrittenOnceAfterThePause() {
        store.saveDelay = 60
        let before = store.fileVersions["shops"] ?? 0
        store.shops = [Shop(name: "K")]
        store.shops[0].name = "Kr"
        store.shops[0].name = "Kroger"
        XCTAssertTrue(store.hasPendingChanges)
        XCTAssertFalse(String(decoding: savedData("shops") ?? Data(), as: UTF8.self).contains("Kroger"), "not written while typing")
        store.savePendingChanges()
        XCTAssertFalse(store.hasPendingChanges)
        XCTAssertTrue(String(decoding: savedData("shops") ?? Data(), as: UTF8.self).contains("Kroger"))
        XCTAssertEqual(store.fileVersions["shops"], before + 1, "three edits, one write")
    }

    func testTheTimerWritesOnItsOwn() {
        store.saveDelay = 0.05
        store.add(name: "Eggs", quantity: 1, aisle: .dairy)
        let written = expectation(description: "written after the pause")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            if !self.store.hasPendingChanges { written.fulfill() }
        }
        wait(for: [written], timeout: 2)
        XCTAssertTrue(String(decoding: savedData("grocery") ?? Data(), as: UTF8.self).contains("Eggs"))
    }

    func testReloadingWritesWaitingChangesFirst() {
        store.saveDelay = 60
        store.add(name: "Bread", quantity: 1, aisle: .bakery)
        store.reload()
        XCTAssertFalse(store.hasPendingChanges)
        XCTAssertEqual(store.items.map(\.name), ["Bread"])
        XCTAssertTrue(String(decoding: savedData("grocery") ?? Data(), as: UTF8.self).contains("Bread"))
    }

    func testSyncLooksOnlyAtFilesThatChanged() {
        let baseline = CloudBaseline(folder: nil)
        XCTAssertEqual(Set(store.cloudFilesChanged(since: baseline)), Set(GroceryStore.cloudFileNames), "first look checks everything")
        let checked = store.fileVersions.merging(Dictionary(uniqueKeysWithValues: GroceryStore.cloudFileNames.map { ($0, 0) })) { a, _ in a }
        XCTAssertTrue(store.cloudFilesChanged(since: baseline, checked: checked).isEmpty, "nothing changed since")
        store.add(name: "Rice", quantity: 1, aisle: .pantry)
        XCTAssertEqual(Set(store.cloudFilesChanged(since: baseline, checked: checked)), ["grocery", "history"])
    }
}
