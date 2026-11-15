import CloudKit
import Foundation
import OSLog

/// Where sync problems are written, for Console.app and sysdiagnoses. Nothing here leaves the phone.
let syncLog = Logger(subsystem: "com.beauregardhenry.makingroceries", category: "Sync")

/// Which CloudKit database a zone lives in: your private one, or the shared one (lists others shared with you).
enum SyncScope: String {
    case `private`, shared
}

/// How a zone's syncing is going, for iCloud Sync's and Family Sharing's screens.
enum SyncStatus: Equatable {
    case off
    case checking
    case noAccount
    case syncing
    case upToDate(Date)
    case failed(String)
}

/// One iCloud zone kept in step with some of the app's files: iCloud Sync's "Groceries" zone, or Family Sharing's
/// "Family" zone (yours, or someone else's that you joined). Each file is one record holding the file's bytes,
/// merged with `GroceryStore`'s three-way merge against the copy both sides last agreed on (the baseline).
///
/// Safety rules: the first merge on a phone combines and never deletes; a record deleted in iCloud never deletes
/// anything here; a copy this version can't read is left alone.
@MainActor
final class SyncZone {
    let zoneID: CKRecordZone.ID
    let scope: SyncScope
    /// The files this zone carries, in the order they're merged (files others point into come first).
    let fileNames: [String]
    /// Family Sharing lines this phone's entries up with the family's before the first merge of each file.
    let linesUpOnFirstMerge: Bool
    weak var store: GroceryStore?

    /// How it's going, for the screen that owns this zone.
    var onStatus: (SyncStatus) -> Void = { _ in }
    /// The zone was deleted in iCloud (or this phone lost access to it).
    var onZoneGone: () -> Void = {}
    /// iCloud signed in, out, or switched accounts.
    var onAccountChange: (CKSyncEngine.Event.AccountChange.ChangeType) -> Void = { _ in }

    private let folder: URL
    private var baseline: CloudBaseline
    /// The store's `fileVersions` when files were last compared with the baseline; empty means compare them all.
    private var checked: [String: Int] = [:]
    /// The bytes sent for each record and not yet confirmed, which become the baseline once saved.
    private var inFlight: [String: Data] = [:]
    private var failed = false

    init(zoneID: CKRecordZone.ID, scope: SyncScope, fileNames: [String], folder: URL, linesUpOnFirstMerge: Bool = false) {
        self.zoneID = zoneID
        self.scope = scope
        self.fileNames = fileNames
        self.folder = folder
        self.linesUpOnFirstMerge = linesUpOnFirstMerge
        baseline = CloudBaseline(folder: folder)
    }

    /// The record type every synced file uses. It already exists in the app's iCloud schema.
    static let recordType = "DataFile"

    /// Whether this phone may create the zone: only its own zones, in its private database.
    var ownsZone: Bool { scope == .private }

    // MARK: Status

    func report(_ status: SyncStatus) {
        if case .failed = status { failed = true } else if case .syncing = status { failed = false }
        onStatus(status)
    }

    /// After a successful fetch or send: up to date, unless something failed on the way.
    func reportUpToDate() {
        if !failed { onStatus(.upToDate(Date())) }
    }

    // MARK: What to send

    /// The record IDs of files that differ from what iCloud last had.
    func changedRecordIDs() -> [CKRecord.ID] {
        guard let store else { return [] }
        let changed = store.cloudFilesChanged(since: baseline, checked: checked).filter(fileNames.contains)
        checked = store.fileVersions
        return changed.map { CKRecord.ID(recordName: $0, zoneID: zoneID) }
    }

    /// The record to send for a file: the last known server record (so iCloud sees it as an update), carrying
    /// this phone's current copy.
    func record(for id: CKRecord.ID) -> CKRecord? {
        let name = id.recordName
        guard fileNames.contains(name), let data = store?.cloudData(for: name) else { return nil }
        let record = savedRecord(name) ?? CKRecord(recordType: SyncZone.recordType, recordID: id)
        let file = FileManager.default.temporaryDirectory.appending(path: "sync-\(zoneID.zoneName)-\(name)-\(UUID().uuidString).json")
        do {
            try data.write(to: file, options: .atomic)
        } catch {
            syncLog.error("Couldn't stage \(name, privacy: .public) for upload: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        record["data"] = CKAsset(fileURL: file)
        inFlight[name] = data
        return record
    }

    // MARK: What came back

    /// Merges a copy from iCloud. Returns true when this phone had changes iCloud doesn't, so it needs sending.
    @discardableResult
    func receive(_ record: CKRecord) -> Bool {
        let name = record.recordID.recordName
        guard record.recordType == SyncZone.recordType, record.recordID.zoneID == zoneID, fileNames.contains(name),
              let store else { return false }
        guard let url = (record["data"] as? CKAsset)?.fileURL else {
            syncLog.error("\(name, privacy: .public) arrived without its data")
            return false
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            syncLog.error("Couldn't read \(name, privacy: .public) from iCloud: \(error.localizedDescription, privacy: .public)")
            return false
        }
        saveFields(of: record)
        if linesUpOnFirstMerge, baseline[name] == nil { store.adoptFamilyIDs(name: name, remote: data) }
        guard let merged = store.applyCloudCopy(name: name, remote: data, base: baseline[name]) else {
            syncLog.error("\(name, privacy: .public) from iCloud couldn't be read; left alone")
            report(.failed("Some of this was saved by a newer version of the app. Update the app to see it."))
            return false
        }
        baseline[name] = data
        return merged != data
    }

    /// iCloud confirmed a save: what was sent becomes the copy both sides agree on.
    func saved(_ record: CKRecord) {
        let name = record.recordID.recordName
        saveFields(of: record)
        if let data = inFlight.removeValue(forKey: name) { baseline[name] = data }
    }

    /// A save didn't go through; the file is compared again next time so it's retried.
    func failedToSave(_ id: CKRecord.ID) {
        checked[id.recordName] = nil
        inFlight[id.recordName] = nil
    }

    /// The saved server fields for a record are out of date (iCloud doesn't know it); send it as new.
    func forgetFields(_ name: String) {
        try? FileManager.default.removeItem(at: fieldsURL(name))
    }

    /// Forgets what iCloud last had, so the next sync combines instead of merging. Nothing in the lists changes.
    func reset() {
        baseline.reset()
        checked = [:]
        inFlight = [:]
        for name in fileNames { forgetFields(name) }
    }

    /// Removes everything this zone kept on the phone (when sync or sharing is turned off). The lists stay.
    func removeLocalState() {
        reset()
        try? FileManager.default.removeItem(at: folder)
        baseline = CloudBaseline(folder: folder)
    }

    // MARK: Saved record fields

    private func fieldsURL(_ name: String) -> URL { folder.appending(path: "fields-\(name).data") }

    private func saveFields(of record: CKRecord) {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try coder.encodedData.write(to: fieldsURL(record.recordID.recordName), options: .atomic)
        } catch {
            // Not fatal: without them the next save conflicts once and is merged.
            syncLog.error("Couldn't save fields for \(record.recordID.recordName, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    private func savedRecord(_ name: String) -> CKRecord? {
        guard let data = try? Data(contentsOf: fieldsURL(name)),
              let coder = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        coder.requiresSecureCoding = true
        defer { coder.finishDecoding() }
        return CKRecord(coder: coder)
    }
}

