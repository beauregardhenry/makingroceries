import CloudKit
import SwiftUI

/// Keeps the lists in step across your devices through iCloud (your private CloudKit database). Each saved file
/// is one record in the "Groceries" zone; `SyncEngines` sends and fetches, `SyncZone` merges (see
/// GroceryStore+Cloud.swift). Off until you turn it on in Settings.
///
/// Safety rules: the first sync on a device combines, never deletes; a record deleted in the cloud never deletes
/// anything here; a copy this version can't read is left alone.
@Observable
final class CloudSync {
    typealias Status = SyncStatus

    private(set) var status: Status = .off

    static let containerID = "iCloud.com.beauregardhenry.makingroceries"
    static let recordType = SyncEngines.recordType

    static var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: "iCloudSync") }
        set { UserDefaults.standard.set(newValue, forKey: "iCloudSync") }
    }

    @ObservationIgnored private var zone: SyncZone?
    private static let folder = Storage.directory.appending(path: "CloudSync", directoryHint: .isDirectory)

    // MARK: Starting and stopping

    @MainActor
    func start(store: GroceryStore) {
        guard Self.enabled else { stop(); return }
        if let zone, SyncEngines.shared.isSyncing(zone) {
            SyncEngines.shared.refresh(zone)
            return
        }
        status = .checking
        Task { @MainActor in
            let account = try? await SyncEngines.shared.container.accountStatus()
            guard Self.enabled, zone.map({ !SyncEngines.shared.isSyncing($0) }) ?? true else { return }
            guard account == .available else {
                status = .noAccount
                return
            }
            let zone = makeZone(store: store)
            self.zone = zone
            SyncEngines.shared.add(zone)
            SyncEngines.shared.refresh(zone)
        }
    }

    @MainActor
    private func makeZone(store: GroceryStore) -> SyncZone {
        let zone = SyncZone(zoneID: CKRecordZone.ID(zoneName: "Groceries", ownerName: CKCurrentUserDefaultName),
                            scope: .private, fileNames: GroceryStore.cloudFileNames, folder: Self.folder)
        zone.store = store
        zone.onStatus = { [weak self] in self?.status = $0 }
        zone.onZoneGone = { [weak zone] in
            // Our zone was deleted (say, from iCloud settings). Keep the lists and upload them again.
            guard let zone else { return }
            zone.reset()
            SyncEngines.shared.recreate(zone)
        }
        zone.onAccountChange = { [weak self, weak zone] change in
            guard let zone else { return }
            switch change {
            case .signIn:
                zone.reset()
                SyncEngines.shared.queueChanges(of: zone)
            case .signOut, .switchAccounts:
                // Keep everything on this device; combine afresh with whichever account comes next.
                zone.reset()
                self?.status = .noAccount
            @unknown default:
                break
            }
        }
        return zone
    }

    /// Turns sync off on this device. Nothing is deleted, here or in iCloud; turning it back on
    /// combines this device's lists with iCloud's again.
    @MainActor
    func stop() {
        if let zone {
            SyncEngines.shared.remove(zone)
            zone.removeLocalState()
        }
        zone = nil
        status = .off
    }

    /// Fetches what other devices changed and sends what changed here.
    @MainActor
    func refresh() {
        if let zone { SyncEngines.shared.refresh(zone) }
    }

    /// Queues every file that differs from what iCloud last had. Called when the lists change.
    @MainActor
    func scheduleUpload() {
        if let zone { SyncEngines.shared.queueChanges(of: zone) }
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
