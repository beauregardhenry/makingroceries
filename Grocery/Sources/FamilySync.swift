import CloudKit
import SwiftUI

/// Family Sharing: one list shared with family members on their own Apple IDs, through CloudKit sharing.
///
/// Whoever shares keeps the list in a "Family" zone in their private iCloud database and shares the whole
/// zone; everyone who accepts the invite sees that zone in their shared database. Each shared file
/// (`GroceryStore.familyFileNames`) is one record, merged the same way as iCloud Sync. The records use iCloud
/// Sync's record type, so the iCloud schema needs nothing new; iCloud Sync only reads its own zone.
///
/// Safety rules, as for iCloud Sync: joining combines and never deletes; when sharing ends, everyone keeps the
/// list as it was; a copy this version can't read is left alone.
@Observable
final class FamilySync: @unchecked Sendable {
    /// One for the app, so an invite opened from Messages can reach it before any screen exists.
    static let shared = FamilySync()

    enum Role: String {
        case none, owner, member
    }

    enum Status: Equatable {
        case off
        case checking
        case noAccount
        case syncing
        case upToDate(Date)
        case failed(String)
    }

    private(set) var role: Role
    private(set) var status: Status = .off
    /// Whose list this phone joined, for a member.
    private(set) var ownerName: String?
    /// Something to tell you once: you joined a list, or sharing ended from another phone.
    var notice: String?

    private static let zoneName = "Family"
    private static let folder = Storage.directory.appending(path: "FamilySync", directoryHint: .isDirectory)

    @ObservationIgnored private weak var store: GroceryStore?
    @ObservationIgnored private var engine: CKSyncEngine?
    @ObservationIgnored private var baseline = CloudBaseline(folder: FamilySync.folder)
    /// The bytes sent for each record and not yet confirmed, which become the baseline once saved.
    @ObservationIgnored private var inFlight: [String: Data] = [:]
    /// The store's `fileVersions` when files were last compared with the baseline; empty means compare them all.
    @ObservationIgnored private var checked: [String: Int] = [:]
    @ObservationIgnored private lazy var container = CKContainer(identifier: CloudSync.containerID)

    private init() {
        let defaults = UserDefaults.standard
        role = Role(rawValue: defaults.string(forKey: "familyRole") ?? "") ?? .none
        ownerName = defaults.string(forKey: "familyOwnerName")
    }

    /// The shared zone: your own for an owner, the owner's (as seen from your shared database) for a member.
    private var zoneID: CKRecordZone.ID? {
        switch role {
        case .none: nil
        case .owner: CKRecordZone.ID(zoneName: Self.zoneName, ownerName: CKCurrentUserDefaultName)
        case .member: UserDefaults.standard.string(forKey: "familyZoneOwner").map {
            CKRecordZone.ID(zoneName: UserDefaults.standard.string(forKey: "familyZoneName") ?? Self.zoneName, ownerName: $0)
        }
        }
    }

    private var database: CKDatabase {
        role == .member ? container.sharedCloudDatabase : container.privateCloudDatabase
    }

    // MARK: Starting and stopping

    @MainActor
    func start(store: GroceryStore) {
        self.store = store
        guard role != .none, zoneID != nil else { status = .off; return }
        if engine != nil {
            refresh()
            return
        }
        status = .checking
        Task { @MainActor in
            let account = try? await container.accountStatus()
            guard role != .none, engine == nil else { return }
            guard account == .available else {
                status = .noAccount
                return
            }
            startEngine()
        }
    }

    @MainActor
    private func startEngine() {
        guard let zoneID else { return }
        let saved = loadState()
        let engine = CKSyncEngine(CKSyncEngine.Configuration(database: database, stateSerialization: saved, delegate: self))
        self.engine = engine
        if saved == nil, role == .owner {
            engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
        }
        UIApplication.shared.registerForRemoteNotifications()
        refresh()
    }

    /// Fetches what family members changed and sends what changed here.
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

    /// Queues every shared file that differs from what the family list last had. Called when the lists change.
    @MainActor
    func scheduleUpload() {
        guard let engine, let store, let zoneID else { return }
        let changed = store.cloudFilesChanged(since: baseline, checked: checked).filter(GroceryStore.familyFileNames.contains)
        checked = store.fileVersions
        guard !changed.isEmpty else { return }
        engine.state.add(pendingRecordZoneChanges: changed.map { .saveRecord(CKRecord.ID(recordName: $0, zoneID: zoneID)) })
    }

    /// Leaves sharing on this phone only: the list stays as it is, and nothing is deleted anywhere.
    @MainActor
    func endLocally(notice: String? = nil) {
        engine = nil
        inFlight = [:]
        baseline.reset()
        checked = [:]
        try? FileManager.default.removeItem(at: Self.folder)
        baseline = CloudBaseline(folder: Self.folder)
        for key in ["familyRole", "familyOwnerName", "familyZoneOwner", "familyZoneName"] {
            UserDefaults.standard.removeObject(forKey: key)
        }
        role = .none
        ownerName = nil
        status = .off
        if let notice { self.notice = notice }
    }

    // MARK: Sharing

    /// Starts sharing this phone's list: makes the family zone and its share, then starts sending the list.
    /// Returns the share to invite people with. If you already share, returns the existing share.
    @MainActor
    func startSharing(title: String) async throws -> CKShare {
        let zoneID = CKRecordZone.ID(zoneName: Self.zoneName, ownerName: CKCurrentUserDefaultName)
        let database = container.privateCloudDatabase
        let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID)
        let share: CKShare
        if let existing = try? await database.record(for: shareID) as? CKShare {
            share = existing
            // Keep the invite's title in step with your name; an old title is no reason to fail.
            if existing[CKShare.SystemFieldKey.title] as? String != title {
                existing[CKShare.SystemFieldKey.title] = title
                _ = try? await database.modifyRecords(saving: [existing], deleting: [])
            }
        } else {
            _ = try await database.modifyRecordZones(saving: [CKRecordZone(zoneID: zoneID)], deleting: [])
            let new = CKShare(recordZoneID: zoneID)
            new[CKShare.SystemFieldKey.title] = title
            new.publicPermission = .none
            let saved = try await database.modifyRecords(saving: [new], deleting: [])
            if case .failure(let error) = saved.saveResults[new.recordID] { throw error }
            share = new
        }
        UserDefaults.standard.set(Role.owner.rawValue, forKey: "familyRole")
        role = .owner
        if let store { start(store: store) }
        return share
    }

    /// The share this phone owns or joined, to see or change who's on the list.
    @MainActor
    func currentShare() async throws -> CKShare {
        guard let zoneID else { throw CKError(.unknownItem) }
        let record = try await database.record(for: CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID))
        guard let share = record as? CKShare else { throw CKError(.unknownItem) }
        return share
    }

    var cloudContainer: CKContainer { container }

    /// Joins a family list from an invite opened on this phone. This phone's list is combined with the family's.
    @MainActor
    func accept(_ metadata: CKShare.Metadata) {
        guard metadata.containerIdentifier == CloudSync.containerID else { return }
        guard role != .owner else {
            notice = "You're sharing your own list. To join this one instead, stop sharing yours in Settings › Family Sharing, then open the invite again."
            return
        }
        Task { @MainActor in
            do {
                if metadata.participantStatus != .accepted { _ = try await container.accept(metadata) }
                let zone = metadata.share.recordID.zoneID
                if role == .member, zone != zoneID { endLocally() }
                let name = metadata.ownerIdentity.nameComponents.map { PersonNameComponentsFormatter.localizedString(from: $0, style: .default) }
                let defaults = UserDefaults.standard
                defaults.set(zone.ownerName, forKey: "familyZoneOwner")
                defaults.set(zone.zoneName, forKey: "familyZoneName")
                defaults.set(name, forKey: "familyOwnerName")
                defaults.set(Role.member.rawValue, forKey: "familyRole")
                ownerName = name
                role = .member
                if let store { start(store: store) }
                notice = "You joined \(name.map { "\($0)'s" } ?? "the family") list. Your own items were added to it."
            } catch {
                notice = "Couldn't join the list: \(error.localizedDescription)"
            }
        }
    }

    // MARK: Records

    /// The record to send for a file: the last known server record (so iCloud sees it as an update),
    /// carrying this phone's current copy.
    @MainActor
    private func record(for id: CKRecord.ID) -> CKRecord? {
        let name = id.recordName
        guard GroceryStore.familyFileNames.contains(name), let data = store?.cloudData(for: name) else { return nil }
        let record = savedRecord(name) ?? CKRecord(recordType: CloudSync.recordType, recordID: id)
        let file = FileManager.default.temporaryDirectory.appending(path: "family-\(name)-\(UUID().uuidString).json")
        guard (try? data.write(to: file, options: .atomic)) != nil else { return nil }
        record["data"] = CKAsset(fileURL: file)
        inFlight[name] = data
        return record
    }

    /// Merges a copy from the family list. The first time, this phone's matching stores, people and items take
    /// the family's ids first. If this phone had changes the family list doesn't, they're sent back.
    @MainActor
    private func receive(_ record: CKRecord) {
        let name = record.recordID.recordName
        guard record.recordType == CloudSync.recordType, record.recordID.zoneID == zoneID,
              GroceryStore.familyFileNames.contains(name),
              let url = (record["data"] as? CKAsset)?.fileURL, let data = try? Data(contentsOf: url), let store else { return }
        saveFields(of: record)
        if baseline[name] == nil { store.adoptFamilyIDs(name: name, remote: data) }
        guard let merged = store.applyCloudCopy(name: name, remote: data, base: baseline[name]) else { return }
        baseline[name] = data
        if merged != data { engine?.state.add(pendingRecordZoneChanges: [.saveRecord(record.recordID)]) }
    }

    // MARK: Saved engine state and record fields

    private func loadState() -> CKSyncEngine.State.Serialization? {
        guard let data = try? Data(contentsOf: Self.folder.appending(path: "engine-state.json")) else { return nil }
        return try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: data)
    }

    private func saveState(_ state: CKSyncEngine.State.Serialization) {
        guard role != .none, let data = try? JSONEncoder().encode(state) else { return }
        try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        try? data.write(to: Self.folder.appending(path: "engine-state.json"), options: .atomic)
    }

    private func saveFields(of record: CKRecord) {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder)
        try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        try? coder.encodedData.write(to: Self.folder.appending(path: "fields-\(record.recordID.recordName).data"), options: .atomic)
    }

    private func forgetFields(_ name: String) {
        try? FileManager.default.removeItem(at: Self.folder.appending(path: "fields-\(name).data"))
    }

    private func savedRecord(_ name: String) -> CKRecord? {
        guard let data = try? Data(contentsOf: Self.folder.appending(path: "fields-\(name).data")),
              let coder = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        coder.requiresSecureCoding = true
        defer { coder.finishDecoding() }
        return CKRecord(coder: coder)
    }
}

extension FamilySync: CKSyncEngineDelegate {
    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        // An engine left over from before sharing ended or changed has nothing more to do.
        guard await MainActor.run(body: { syncEngine === self.engine }) else { return }
        switch event {
        case .stateUpdate(let update):
            saveState(update.stateSerialization)

        case .accountChange(let change):
            await MainActor.run {
                switch change.changeType {
                case .signIn:
                    break
                case .signOut, .switchAccounts:
                    endLocally(notice: "This phone left the family list because iCloud signed out. Your list stays here.")
                @unknown default:
                    break
                }
            }

        case .fetchedDatabaseChanges(let changes):
            await MainActor.run {
                guard let zoneID, changes.deletions.contains(where: { $0.zoneID == zoneID }) else { return }
                if role == .member {
                    endLocally(notice: "The family list is no longer shared with you. Your list stays on this phone as it was.")
                } else {
                    // Our zone was deleted (say, from iCloud settings), which also ends the share. Keep the list.
                    endLocally(notice: "Family Sharing stopped because its iCloud data was removed. Your list stays on this phone.")
                }
            }

        case .fetchedRecordZoneChanges(let changes):
            // Deletions are ignored on purpose: nothing in iCloud can delete lists on this phone.
            await MainActor.run {
                let order = GroceryStore.familyFileNames
                let records = changes.modifications.map(\.record).sorted {
                    (order.firstIndex(of: $0.recordID.recordName) ?? order.count) < (order.firstIndex(of: $1.recordID.recordName) ?? order.count)
                }
                for record in records { receive(record) }
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
                    // Compare this file again next time, so a save that didn't go through is tried again.
                    checked[id.recordName] = nil
                    switch failure.error.code {
                    case .serverRecordChanged:
                        // Someone else saved first: merge their copy, then send the combined one.
                        if let server = failure.error.serverRecord { receive(server) }
                        syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(id)])
                    case .zoneNotFound, .userDeletedZone:
                        if role == .member {
                            endLocally(notice: "The family list is no longer shared with you. Your list stays on this phone as it was.")
                        } else {
                            syncEngine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: id.zoneID))])
                            syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(id)])
                        }
                    case .unknownItem:
                        forgetFields(id.recordName)
                        syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(id)])
                    case .permissionFailure:
                        status = .failed("The list's owner hasn't let you make changes.")
                    case .quotaExceeded:
                        status = .failed(role == .member ? "The owner's iCloud storage is full." : "Your iCloud storage is full.")
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

// MARK: Accepting invites

/// Hands an invite opened from Messages or Mail to Family Sharing, whether the app was running or not.
final class FamilySceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        if let metadata = connectionOptions.cloudKitShareMetadata {
            Task { @MainActor in FamilySync.shared.accept(metadata) }
        }
    }

    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        Task { @MainActor in FamilySync.shared.accept(metadata) }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: session.role)
        configuration.delegateClass = FamilySceneDelegate.self
        return configuration
    }
}

// MARK: Screen

/// Settings › Family Sharing: share your list with family members, or see the list you joined.
struct FamilySharingView: View {
    @Environment(FamilySync.self) private var family
    @Environment(\.dismiss) private var dismiss
    @AppStorage("myName") private var myName = ""
    @State private var share: SharedList?
    /// The share you own, once loaded, so Invite can send it with a message.
    @State private var ownShare: CKShare?
    @State private var working = false
    @State private var problem: String?

    private struct SharedList: Identifiable {
        let share: CKShare
        var id: String { share.recordID.recordName }
    }

    private var statusText: String {
        switch family.status {
        case .off: "Off"
        case .checking: "Checking iCloud…"
        case .noAccount: "Sign in to iCloud in the Settings app to share."
        case .syncing: "Syncing…"
        case .upToDate(let date): "Up to date, \(date.formatted(.relative(presentation: .named)))"
        case .failed(let message): message
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                switch family.role {
                case .none:
                    nameSection
                    Section {
                        ShareLink(item: FamilyInviteItem(family: family, name: myName, existing: nil),
                                  message: Text(FamilyInvite.message(from: myName)),
                                  preview: SharePreview(FamilyInvite.title(from: myName))) {
                            Label("Share My List with Family", systemImage: "person.2.badge.plus")
                        }
                    } footer: {
                        Text("Invite family members by Messages or Mail. Everyone who accepts sees the same list on their own phone, from anywhere, and changes show up for everyone. They need the app and an iCloud account.")
                    }
                    Section {
                        Text("To join someone else's list, open the invite they sent you on this phone. Your items are added to their list; nothing is removed, and stores and items you both have are listed once.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                case .owner, .member:
                    Section {
                        if family.role == .member {
                            LabeledContent("List", value: family.ownerName.map { "\($0)'s" } ?? "Shared with you")
                        } else {
                            LabeledContent("List", value: "Yours, shared")
                        }
                        LabeledContent("Status", value: statusText)
                        Button("Sync Now", systemImage: "arrow.triangle.2.circlepath") { family.refresh() }
                            .disabled(family.status == .checking || family.status == .noAccount)
                    }
                    if family.role == .owner {
                        nameSection
                    }
                    Section {
                        if family.role == .owner, let ownShare {
                            ShareLink(item: FamilyInviteItem(family: family, name: myName, existing: ownShare),
                                      message: Text(FamilyInvite.message(from: myName)),
                                      preview: SharePreview(FamilyInvite.title(from: myName))) {
                                Label("Invite Someone", systemImage: "person.badge.plus")
                            }
                        }
                        Button(family.role == .owner ? "See or Remove People" : "People on This List",
                               systemImage: "person.2") { open() }
                            .disabled(working)
                    } footer: {
                        Text(family.role == .owner
                             ? "To stop sharing, tap See or Remove People, then Stop Sharing. Everyone keeps the list as it was."
                             : "To leave, tap People on This List, then Remove Me. Your list stays on this phone as it was.")
                    }
                }
                Section {
                    Text("Shared: everything. The list (with Travel, Clothing and Registry), stores, aisles, family members and their sizes, Registry people, allergies, meals and the meal plan, the kitchen, spending, prices and the budget, and Save Up with its monthly amount. Only this phone's color, icon and sync settings stay its own.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let problem {
                    Section { Text(problem).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Family Sharing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task(id: family.role) {
                ownShare = family.role == .owner ? try? await family.currentShare() : nil
            }
            .sheet(item: $share) { shared in
                CloudSharingView(share: shared.share, container: family.cloudContainer) {
                    family.endLocally()
                }
                .ignoresSafeArea()
            }
        }
    }

    private var nameSection: some View {
        Section {
            TextField("Your name", text: $myName).titleCase($myName)
        } footer: {
            Text("Invites say who they're from: \"\(FamilyInvite.title(from: myName))\".")
        }
    }

    private func open() {
        working = true
        problem = nil
        Task { @MainActor in
            do {
                let found = family.role == .none
                    ? try await family.startSharing(title: FamilyInvite.title(from: myName))
                    : try await family.currentShare()
                share = SharedList(share: found)
            } catch {
                problem = "Couldn't reach iCloud: \(error.localizedDescription)"
            }
            working = false
        }
    }
}

/// Apple's screen for inviting people to a share, seeing who's on it, and stopping or leaving.
private struct CloudSharingView: UIViewControllerRepresentable {
    let share: CKShare
    let container: CKContainer
    let onStop: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onStop: onStop) }

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: container)
        // Invited people only, and everyone can add and check off.
        controller.availablePermissions = [.allowPrivate, .allowReadWrite]
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: UICloudSharingController, context: Context) {}

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        let onStop: () -> Void
        init(onStop: @escaping () -> Void) { self.onStop = onStop }

        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {}
        func itemTitle(for csc: UICloudSharingController) -> String? { csc.share?[CKShare.SystemFieldKey.title] as? String }
        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
            Task { @MainActor in onStop() }
        }
    }
}

/// What Invite sends: the family share, made the first time, so Messages and Mail send its link with
/// `FamilyInvite.message` above it.
private struct FamilyInviteItem: Transferable {
    let family: FamilySync
    let name: String
    let existing: CKShare?

    static var transferRepresentation: some TransferRepresentation {
        CKShareTransferRepresentation { item in
            let options = CKAllowedSharingOptions(allowedParticipantPermissionOptions: .readWrite,
                                                  allowedParticipantAccessOptions: .specifiedRecipientsOnly)
            if let existing = item.existing {
                return .existing(existing, container: item.family.cloudContainer, allowedSharingOptions: options)
            }
            return .prepareShare(container: item.family.cloudContainer, allowedSharingOptions: options) {
                try await item.family.startSharing(title: FamilyInvite.title(from: item.name))
            }
        }
    }
}
