import CloudKit
import XCTest


@MainActor
final class SyncZoneTests: StoreTestCase {
    private var folder: URL!
    private let zoneID = CKRecordZone.ID(zoneName: "Test", ownerName: CKCurrentUserDefaultName)

    override func setUp() async throws {
        try await super.setUp()
        folder = FileManager.default.temporaryDirectory.appending(path: "SyncZoneTests-\(UUID().uuidString)")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: folder)
        try await super.tearDown()
    }

    private func makeZone(files: [String] = GroceryStore.cloudFileNames, linesUp: Bool = false) -> SyncZone {
        let zone = SyncZone(zoneID: zoneID, scope: .private, fileNames: files, folder: folder, linesUpOnFirstMerge: linesUp)
        zone.store = store
        return zone
    }

    /// A record as iCloud would hand it back, carrying `data` for the file `name`.
    private func remoteRecord(_ name: String, _ data: Data, zone: CKRecordZone.ID? = nil, type: String = SyncZone.recordType) throws -> CKRecord {
        let record = CKRecord(recordType: type, recordID: CKRecord.ID(recordName: name, zoneID: zone ?? zoneID))
        let file = folder.appending(path: "remote-\(name)-\(UUID().uuidString).json")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try data.write(to: file)
        record["data"] = CKAsset(fileURL: file)
        return record
    }

    private func encoded<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(value)
    }

    func testTheFirstLookSendsEverythingThenOnlyWhatChanged() {
        let zone = makeZone(files: ["grocery", "shops"])
        XCTAssertEqual(Set(zone.changedRecordIDs().map(\.recordName)), ["grocery", "shops"])
        XCTAssertTrue(zone.changedRecordIDs().isEmpty, "nothing changed since")
        store.add(name: "Milk", quantity: 1, aisle: .dairy)
        XCTAssertEqual(zone.changedRecordIDs().map(\.recordName), ["grocery"])
    }

    func testTheRecordCarriesThisPhonesCopy() throws {
        store.add(name: "Milk", quantity: 1, aisle: .dairy)
        let zone = makeZone(files: ["grocery"])
        let record = try XCTUnwrap(zone.record(for: CKRecord.ID(recordName: "grocery", zoneID: zoneID)))
        let url = try XCTUnwrap((record["data"] as? CKAsset)?.fileURL)
        XCTAssertEqual(try Data(contentsOf: url), store.cloudData(for: "grocery"))
        XCTAssertNil(zone.record(for: CKRecord.ID(recordName: "meals", zoneID: zoneID)), "not one of this zone's files")
    }

    func testASavedRecordBecomesTheBaselineAndSurvivesARelaunch() throws {
        store.add(name: "Milk", quantity: 1, aisle: .dairy)
        let zone = makeZone(files: ["grocery"])
        let record = try XCTUnwrap(zone.record(for: CKRecord.ID(recordName: "grocery", zoneID: zoneID)))
        zone.saved(record)
        let relaunched = makeZone(files: ["grocery"])
        XCTAssertTrue(relaunched.changedRecordIDs().isEmpty, "iCloud already has this copy")
        XCTAssertEqual(relaunched.record(for: record.recordID)?.recordID, record.recordID, "sent as an update of the saved record")
    }

    func testAFailedSaveIsTriedAgain() throws {
        let zone = makeZone(files: ["grocery"])
        let id = try XCTUnwrap(zone.changedRecordIDs().first)
        _ = zone.record(for: id)
        XCTAssertTrue(zone.changedRecordIDs().isEmpty)
        zone.failedToSave(id)
        XCTAssertEqual(zone.changedRecordIDs(), [id])
    }

    func testReceivingMergesAndSaysWhenThisPhoneHasMore() throws {
        store.add(name: "Milk", quantity: 1, aisle: .dairy)
        let zone = makeZone(files: ["grocery"])
        let theirs = [GroceryItem(name: "Eggs", aisle: .dairy)]
        XCTAssertTrue(zone.receive(try remoteRecord("grocery", try encoded(theirs))), "Milk still needs sending")
        XCTAssertEqual(Set(store.items.map(\.name)), ["Milk", "Eggs"], "the first merge combines")
        let same = try XCTUnwrap(store.cloudData(for: "grocery"))
        XCTAssertFalse(zone.receive(try remoteRecord("grocery", same)), "nothing more to send")
    }

    func testRecordsFromElsewhereAreIgnored() throws {
        let zone = makeZone(files: ["grocery"])
        let data = try encoded([GroceryItem(name: "Eggs", aisle: .dairy)])
        let otherZone = CKRecordZone.ID(zoneName: "Other", ownerName: CKCurrentUserDefaultName)
        XCTAssertFalse(zone.receive(try remoteRecord("grocery", data, zone: otherZone)))
        XCTAssertFalse(zone.receive(try remoteRecord("grocery", data, type: "SomethingElse")))
        XCTAssertFalse(zone.receive(try remoteRecord("meals", data)))
        XCTAssertFalse(zone.receive(CKRecord(recordType: SyncZone.recordType, recordID: CKRecord.ID(recordName: "grocery", zoneID: zoneID))))
        XCTAssertTrue(store.items.isEmpty)
    }

    func testACopyThisVersionCantReadIsLeftAloneAndReported() throws {
        store.add(name: "Milk", quantity: 1, aisle: .dairy)
        let zone = makeZone(files: ["grocery"])
        var reported: SyncStatus?
        zone.onStatus = { reported = $0 }
        XCTAssertFalse(zone.receive(try remoteRecord("grocery", Data("{\"future\": true}".utf8))))
        XCTAssertEqual(store.items.map(\.name), ["Milk"])
        guard case .failed(let message) = reported else { return XCTFail("not reported") }
        XCTAssertTrue(message.contains("newer version"))
        zone.reportUpToDate()
        if case .upToDate = reported { XCTFail("a problem isn't hidden by the next sync") }
        zone.report(.syncing)
        zone.reportUpToDate()
        guard case .upToDate = reported else { return XCTFail("a new sync clears it") }
    }

    func testFamilyZonesLineUpBeforeTheFirstMerge() throws {
        let mine = Shop(name: "Kroger")
        store.shops = [mine]
        let zone = makeZone(files: ["shops"], linesUp: true)
        let family = Shop(name: "kroger")
        zone.receive(try remoteRecord("shops", try encoded([family])))
        XCTAssertEqual(store.shops.map(\.id), [family.id])
    }

    func testResettingAndRemovingKeepTheLists() throws {
        store.add(name: "Milk", quantity: 1, aisle: .dairy)
        let zone = makeZone(files: ["grocery"])
        let record = try XCTUnwrap(zone.record(for: CKRecord.ID(recordName: "grocery", zoneID: zoneID)))
        zone.saved(record)
        zone.reset()
        XCTAssertEqual(zone.changedRecordIDs().map(\.recordName), ["grocery"], "after a reset everything is sent again")
        zone.forgetFields("grocery")
        zone.removeLocalState()
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
        XCTAssertEqual(store.items.map(\.name), ["Milk"])
        XCTAssertTrue(zone.ownsZone)
    }
}
