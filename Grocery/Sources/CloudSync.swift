import CloudKit
import SwiftUI

/// Keeps the lists in step across your devices through iCloud (your private CloudKit database), using
/// CKSyncEngine to send and fetch. Each saved file is one record; merging happens in
/// GroceryStore+Cloud.swift. Off until you turn it on in Settings.
///
/// Safety rules: the first sync on a device combines, never deletes; a record deleted in the cloud
/// never deletes anything here; a copy this version can't read is left alone.
@Observable
final class CloudSync: @unchecked Sendable {
    enum Status: Equatable {
        case off
        case checking
        case noAccount
        case syncing
        case upToDate(Date)
        case failed(String)
    }

    private(set) var status: Status = .off

    static let containerID = "iCloud.com.beauregardhenry.makingroceries"
    static let recordType = "DataFile"

    static var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: "iCloudSync") }
        set { UserDefaults.standard.set(newValue, forKey: "iCloudSync") }
    }

    @ObservationIgnored private weak var store: GroceryStore?
    @ObservationIgnored private var engine: CKSyncEngine?
    @ObservationIgnored private var baseline = CloudBaseline()
    /// The bytes sent for each record and not yet confirmed, which become the baseline once saved.
    @ObservationIgnored private var inFlight: [String: Data] = [:]
    @ObservationIgnored private lazy var container = CKContainer(identifier: Self.containerID)
    private let zoneID = CKRecordZone.ID(zoneName: "Groceries", ownerName: CKCurrentUserDefaultName)
    private let folder = Storage.directory.appending(path: "CloudSync", directoryHint: .isDirectory)

    // MARK: Starting and stopping

    @MainActor
    func start(store: GroceryStore) {
        self.store = store
        guard Self.enabled else { stop(); return }
        if engine != nil {
            refresh()
            return
        }
        status = .checking
        Task { @MainActor in
            let account = try? await container.accountStatus()
            guard Self.enabled, engine == nil else { return }
            guard account == .available else {
                status = .noAccount
                return
            }
            let saved = loadState()
            let engine = CKSyncEngine(CKSyncEngine.Configuration(
                database: container.privateCloudDatabase, stateSerialization: saved, delegate: self))
            self.engine = engine
            if saved == nil {
                engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
            }
            UIApplication.shared.registerForRemoteNotifications()
            refresh()
        }
    }

    /// Turns sync off on this device. Nothing is deleted, here or in iCloud; turning it back on
    /// combines this device's lists with iCloud's again.
    @MainActor
    func stop() {
        engine = nil
        inFlight = [:]
        baseline.reset()
        try? FileManager.default.removeItem(at: folder.appending(path: "engine-state.json"))
        for name in GroceryStore.cloudFileNames {
            try? FileManager.default.removeItem(at: folder.appending(path: "fields-\(name).data"))
        }
        status = .off
    }

    /// Fetches what other devices changed and sends what changed here.
    @MainActor
    func refresh() {
        guard let engine else { return }
        status = .syncing
        scheduleUpload()
        Task {
            try? await engine.fetchChanges()
            try? await engine.sendChanges()
            await MainActor.run { if case .syncing = self.status { self.status = .upToDate(Date()) } }
        }
    }

    /// Queues every file that differs from what iCloud last had. Called when the lists change.
    @MainActor
    func scheduleUpload() {
        guard let engine, let store else { return }
        let changed = store.cloudFilesChanged(since: baseline)
        guard !changed.isEmpty else { return }
        engine.state.add(pendingRecordZoneChanges: changed.map { .saveRecord(recordID($0)) })
    }

    // MARK: Records

    private func recordID(_ name: String) -> CKRecord.ID {
        CKRecord.ID(recordName: name, zoneID: zoneID)
    }

    /// The record to send for a file: the last known server record (so iCloud sees it as an update),
    /// carrying this device's current copy.
    @MainActor
    private func record(for id: CKRecord.ID) -> CKRecord? {
        let name = id.recordName
        guard let data = store?.cloudData(for: name) else { return nil }
        let record = savedRecord(name) ?? CKRecord(recordType: Self.recordType, recordID: id)
        let file = FileManager.default.temporaryDirectory.appending(path: "cloud-\(name)-\(UUID().uuidString).json")
        guard (try? data.write(to: file, options: .atomic)) != nil else { return nil }
        record["data"] = CKAsset(fileURL: file)
        inFlight[name] = data
        return record
    }

    /// Merges a copy that came from iCloud. If this device had changes iCloud doesn't, they're sent back.
    @MainActor
    private func receive(_ record: CKRecord) {
        guard record.recordType == Self.recordType,
              let url = (record["data"] as? CKAsset)?.fileURL, let data = try? Data(contentsOf: url) else { return }
        let name = record.recordID.recordName
        saveFields(of: record)
        guard let store, let merged = store.applyCloudCopy(name: name, remote: data, base: baseline[name]) else { return }
        baseline[name] = data
        if merged != data { engine?.state.add(pendingRecordZoneChanges: [.saveRecord(record.recordID)]) }
    }

    // MARK: Saved engine state and record fields

    private func loadState() -> CKSyncEngine.State.Serialization? {
        guard let data = try? Data(contentsOf: folder.appending(path: "engine-state.json")) else { return nil }
        return try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: data)
    }

    private func saveState(_ state: CKSyncEngine.State.Serialization) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? data.write(to: folder.appending(path: "engine-state.json"), options: .atomic)
    }

    private func saveFields(of record: CKRecord) {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? coder.encodedData.write(to: folder.appending(path: "fields-\(record.recordID.recordName).data"), options: .atomic)
    }

    private func forgetFields(_ name: String) {
        try? FileManager.default.removeItem(at: folder.appending(path: "fields-\(name).data"))
    }

    private func savedRecord(_ name: String) -> CKRecord? {
        guard let data = try? Data(contentsOf: folder.appending(path: "fields-\(name).data")),
              let coder = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        coder.requiresSecureCoding = true
        defer { coder.finishDecoding() }
        return CKRecord(coder: coder)
    }
}

extension CloudSync: CKSyncEngineDelegate {
    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case .stateUpdate(let update):
            saveState(update.stateSerialization)

        case .accountChange(let change):
            await MainActor.run {
                switch change.changeType {
                case .signIn:
                    baseline.reset()
                    scheduleUpload()
                case .signOut, .switchAccounts:
                    // Keep everything on this device; combine afresh with whichever account comes next.
                    baseline.reset()
                    status = .noAccount
                @unknown default:
                    break
                }
            }

        case .fetchedDatabaseChanges(let changes):
            // Our zone was deleted (say, from iCloud settings). Keep the lists and upload them again.
            if changes.deletions.contains(where: { $0.zoneID == zoneID }) {
                await MainActor.run {
                    baseline.reset()
                    for name in GroceryStore.cloudFileNames { forgetFields(name) }
                    syncEngine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
                    scheduleUpload()
                }
            }

        case .fetchedRecordZoneChanges(let changes):
            // Deletions are ignored on purpose: nothing in iCloud can delete lists on this device.
            await MainActor.run {
                for modification in changes.modifications { receive(modification.record) }
            }

        case .sentRecordZoneChanges(let sent):
            await MainActor.run {
                for record in sent.savedRecords {
                    let name = record.recordID.recordName
                    saveFields(of: record)
                    if let data = inFlight.removeValue(forKey: name) { baseline[name] = data }
                }
                for failure in sent.failedRecordSaves {
                    let id = failure.record.recordID
                    switch failure.error.code {
                    case .serverRecordChanged:
                        // Another device saved first: merge its copy, then send the combined one.
                        if let server = failure.error.serverRecord { receive(server) }
                        syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(id)])
                    case .zoneNotFound:
                        syncEngine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
                        syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(id)])
                    case .unknownItem:
                        forgetFields(id.recordName)
                        syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(id)])
                    case .quotaExceeded:
                        status = .failed("Your iCloud storage is full.")
                    case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited:
                        break // CKSyncEngine retries these on its own.
                    default:
                        status = .failed(failure.error.localizedDescription)
                    }
                }
            }

        case .didSendChanges, .didFetchChanges:
            await MainActor.run {
                if case .failed = status { return }
                status = .upToDate(Date())
            }

        default:
            break
        }
    }

    func nextRecordZoneChangeBatch(_ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let pending = syncEngine.state.pendingRecordZoneChanges.filter { context.options.scope.contains($0) }
        guard !pending.isEmpty else { return nil }
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pending) { id in
            await MainActor.run { self.record(for: id) }
        }
    }
}

/// Settings › iCloud Sync: turn it on, see whether it's up to date, and sync now.
struct CloudSyncView: View {
    @Environment(GroceryStore.self) private var store
    @Environment(CloudSync.self) private var sync
    @Environment(\.dismiss) private var dismiss
    @State private var enabled = CloudSync.enabled

    private var statusText: String {
        switch sync.status {
        case .off: "Off"
        case .checking: "Checking iCloud…"
        case .noAccount: "Sign in to iCloud in the Settings app to sync."
        case .syncing: "Syncing…"
        case .upToDate(let date): "Up to date, \(date.formatted(.relative(presentation: .named)))"
        case .failed(let message): message
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Sync with iCloud", isOn: $enabled)
                } footer: {
                    Text("Your list, stores, meals, history and everything else stay the same on every iPhone, iPad and Mac signed in to your iCloud account. They're kept in your private iCloud storage, which only you can see.")
                }
                if enabled {
                    Section {
                        LabeledContent("Status", value: statusText)
                        Button("Sync Now", systemImage: "arrow.triangle.2.circlepath") { sync.refresh() }
                            .disabled(sync.status == .checking || sync.status == .noAccount)
                    }
                }
                Section {
                    Text("Turning sync on combines this device's lists with what's in iCloud. Nothing is removed. Turning it off keeps everything on this device and in iCloud.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("iCloud Sync")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onChange(of: enabled) { _, on in
                CloudSync.enabled = on
                if on { sync.start(store: store) } else { sync.stop() }
            }
        }
    }
}
