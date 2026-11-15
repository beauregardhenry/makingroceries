import CloudKit
import OSLog
import UIKit

/// The app's CloudKit sync engines: one for the private database (iCloud Sync's zone, and a family list you
/// share) and one for the shared database (a family list you joined). Apple's sync engine is meant to be the
/// only one per database, so iCloud Sync and Family Sharing add their zones here instead of running their own.
@MainActor
final class SyncEngines {
    typealias Scope = SyncScope

    static let shared = SyncEngines()
    static let recordType = SyncZone.recordType

    let container = CKContainer(identifier: CloudSync.containerID)
    private var zones: [CKRecordZone.ID: SyncZone] = [:]
    private var engines: [Scope: CKSyncEngine] = [:]
    private lazy var delegate = EngineDelegate(owner: self)
    private let folder = Storage.directory.appending(path: "SyncEngines", directoryHint: .isDirectory)

    private init() {
        // The engines iCloud Sync and Family Sharing used to run kept their own state; it isn't needed now.
        for old in ["CloudSync", "FamilySync"] {
            try? FileManager.default.removeItem(at: Storage.directory.appending(path: "\(old)/engine-state.json"))
        }
    }

    // MARK: Zones

    /// Starts syncing a zone. A zone new to its engine starts that engine afresh, so it fetches everything,
    /// including changes to this zone it skipped while the zone wasn't being synced.
    func add(_ zone: SyncZone) {
        guard zones[zone.zoneID] !== zone else { return }
        zones[zone.zoneID] = zone
        startEngine(zone.scope, fresh: !knownZones(zone.scope).contains(key(zone)))
        // Every zone on this engine is now covered by its state (a fresh start fetches them all).
        setKnownZones(knownZones(zone.scope).union(zones(on: zone.scope).map(key)), zone.scope)
        if zone.ownsZone {
            engines[zone.scope]?.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zone.zoneID))])
        }
        UIApplication.shared.registerForRemoteNotifications()
    }

    /// Stops syncing a zone. Its engine stops too when it has no zones left. Nothing is deleted in iCloud.
    func remove(_ zone: SyncZone) {
        guard zones[zone.zoneID] === zone else { return }
        zones[zone.zoneID] = nil
        guard let engine = engines[zone.scope] else { return }
        let leftover = engine.state.pendingRecordZoneChanges.filter { change in
            switch change {
            case .saveRecord(let id), .deleteRecord(let id): id.zoneID == zone.zoneID
            @unknown default: false
            }
        }
        engine.state.remove(pendingRecordZoneChanges: leftover)
        var known = knownZones(zone.scope)
        known.remove(key(zone))
        setKnownZones(known, zone.scope)
        if !zones.values.contains(where: { $0.scope == zone.scope }) {
            engines[zone.scope] = nil
            try? FileManager.default.removeItem(at: stateURL(zone.scope))
            setKnownZones([], zone.scope)
        }
    }

    /// The zones an engine's saved state already covers, so relaunching doesn't fetch everything again.
    private func knownZones(_ scope: Scope) -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: "syncEngineZones-\(scope.rawValue)") ?? [])
    }

    private func setKnownZones(_ zones: Set<String>, _ scope: Scope) {
        UserDefaults.standard.set(zones.sorted(), forKey: "syncEngineZones-\(scope.rawValue)")
    }

    private func key(_ zone: SyncZone) -> String { "\(zone.zoneID.zoneName)|\(zone.zoneID.ownerName)" }

    func isSyncing(_ zone: SyncZone) -> Bool { zones[zone.zoneID] === zone }

    /// Queues the zone's changed files and syncs its engine now.
    func refresh(_ zone: SyncZone) {
        guard let engine = engines[zone.scope], isSyncing(zone) else { return }
        zone.report(.syncing)
        queueChanges(of: zone)
        Task {
            try? await engine.fetchChanges()
            try? await engine.sendChanges()
            zone.reportUpToDate()
        }
    }

    /// Makes the zone again after it was deleted in iCloud, then sends everything in it.
    func recreate(_ zone: SyncZone) {
        guard let engine = engines[zone.scope], isSyncing(zone), zone.ownsZone else { return }
        engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zone.zoneID))])
        queueChanges(of: zone)
    }

    /// Queues whatever files of the zone changed since it last looked. Called whenever the lists change.
    func queueChanges(of zone: SyncZone) {
        guard let engine = engines[zone.scope], isSyncing(zone) else { return }
        let ids = zone.changedRecordIDs()
        if !ids.isEmpty { engine.state.add(pendingRecordZoneChanges: ids.map { .saveRecord($0) }) }
    }

    // MARK: Engines

    private func startEngine(_ scope: Scope, fresh: Bool) {
        if fresh {
            engines[scope] = nil
            try? FileManager.default.removeItem(at: stateURL(scope))
            setKnownZones([], scope)
        }
        guard engines[scope] == nil else { return }
        let database = scope == .private ? container.privateCloudDatabase : container.sharedCloudDatabase
        engines[scope] = CKSyncEngine(CKSyncEngine.Configuration(database: database, stateSerialization: loadState(scope),
                                                                 delegate: delegate))
    }

    private func stateURL(_ scope: Scope) -> URL { folder.appending(path: "\(scope.rawValue)-state.json") }

    private func loadState(_ scope: Scope) -> CKSyncEngine.State.Serialization? {
        guard let data = try? Data(contentsOf: stateURL(scope)) else { return nil }
        do {
            return try JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: data)
        } catch {
            syncLog.error("Saved \(scope.rawValue, privacy: .public) sync state couldn't be read; starting afresh")
            return nil
        }
    }

    private func saveState(_ state: CKSyncEngine.State.Serialization, _ scope: Scope) {
        do {
            let data = try JSONEncoder().encode(state)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: stateURL(scope), options: .atomic)
        } catch {
            // Not fatal: the next launch fetches more than it needs to.
            syncLog.error("Couldn't save \(scope.rawValue, privacy: .public) sync state: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func scope(of engine: CKSyncEngine) -> Scope? {
        engines.first { $0.value === engine }?.key
    }

    private func zones(on scope: Scope) -> [SyncZone] {
        zones.values.filter { $0.scope == scope }
    }

    // MARK: Events

    fileprivate func handle(_ event: CKSyncEngine.Event, from engine: CKSyncEngine) {
        // An engine replaced since (sync turned off, a zone added) has nothing more to do.
        guard let scope = scope(of: engine) else { return }
        switch event {
        case .stateUpdate(let update):
            saveState(update.stateSerialization, scope)

        case .accountChange(let change):
            for zone in zones(on: scope) { zone.onAccountChange(change.changeType) }

        case .fetchedDatabaseChanges(let changes):
            for deletion in changes.deletions {
                zones[deletion.zoneID]?.onZoneGone()
            }

        case .fetchedRecordZoneChanges(let changes):
            // Deletions are ignored on purpose: nothing in iCloud can delete lists on this phone.
            let byZone = Dictionary(grouping: changes.modifications.map(\.record), by: \.recordID.zoneID)
            for (zoneID, records) in byZone {
                guard let zone = zones[zoneID] else { continue }
                let order = zone.fileNames
                let sorted = records.sorted {
                    (order.firstIndex(of: $0.recordID.recordName) ?? order.count) < (order.firstIndex(of: $1.recordID.recordName) ?? order.count)
                }
                for record in sorted where zone.receive(record) {
                    engine.state.add(pendingRecordZoneChanges: [.saveRecord(record.recordID)])
                }
            }

        case .sentRecordZoneChanges(let sent):
            for record in sent.savedRecords { zones[record.recordID.zoneID]?.saved(record) }
            for failure in sent.failedRecordSaves {
                let id = failure.record.recordID
                guard let zone = zones[id.zoneID] else { continue }
                zone.failedToSave(id)
                handleFailure(failure.error, for: id, in: zone, engine: engine)
            }

        case .didSendChanges, .didFetchChanges:
            for zone in zones(on: scope) { zone.reportUpToDate() }

        default:
            break
        }
    }

    private func handleFailure(_ error: CKError, for id: CKRecord.ID, in zone: SyncZone, engine: CKSyncEngine) {
        switch error.code {
        case .serverRecordChanged:
            // Another phone saved first: merge its copy, then send the combined one.
            if let server = error.serverRecord { zone.receive(server) }
            engine.state.add(pendingRecordZoneChanges: [.saveRecord(id)])
        case .zoneNotFound, .userDeletedZone:
            if zone.ownsZone {
                engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: id.zoneID))])
                engine.state.add(pendingRecordZoneChanges: [.saveRecord(id)])
            } else {
                zone.onZoneGone()
            }
        case .unknownItem:
            zone.forgetFields(id.recordName)
            engine.state.add(pendingRecordZoneChanges: [.saveRecord(id)])
        case .permissionFailure:
            zone.report(.failed("The list's owner hasn't let you make changes."))
        case .quotaExceeded:
            zone.report(.failed(zone.ownsZone ? "Your iCloud storage is full." : "The list owner's iCloud storage is full."))
        case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited, .zoneBusy:
            break // The sync engine retries these on its own.
        default:
            syncLog.error("Saving \(id.recordName, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            zone.report(.failed(error.localizedDescription))
        }
    }

    fileprivate func nextBatch(_ context: CKSyncEngine.SendChangesContext, engine: CKSyncEngine) -> [CKSyncEngine.PendingRecordZoneChange] {
        engine.state.pendingRecordZoneChanges.filter { context.options.scope.contains($0) }
    }

    fileprivate func record(for id: CKRecord.ID) -> CKRecord? {
        zones[id.zoneID]?.record(for: id)
    }
}

/// Receives the engines' calls (on any thread) and hands them to `SyncEngines` on the main thread.
private final class EngineDelegate: CKSyncEngineDelegate, @unchecked Sendable {
    private weak var owner: SyncEngines?

    init(owner: SyncEngines) { self.owner = owner }

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        await MainActor.run { owner?.handle(event, from: syncEngine) }
    }

    func nextRecordZoneChangeBatch(_ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let pending = await MainActor.run { owner?.nextBatch(context, engine: syncEngine) ?? [] }
        guard !pending.isEmpty else { return nil }
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pending) { id in
            await MainActor.run { self.owner?.record(for: id) }
        }
    }
}
