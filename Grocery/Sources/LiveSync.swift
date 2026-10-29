import MultipeerConnectivity
import SwiftUI

/// Keeps the list in step with other phones in the household, directly over Wi-Fi or Bluetooth, while
/// the app is open on both. Phones find each other only when they use the same household code. Nothing
/// goes through iCloud or any server.
@Observable
final class HouseholdSync: NSObject {
    static let serviceType = "mkgroceries"

    private(set) var connected: [String] = []
    private(set) var isRunning = false
    private(set) var lastReceived: Date?

    @ObservationIgnored private weak var store: GroceryStore?
    @ObservationIgnored private var code = ""
    @ObservationIgnored private var name = "iPhone"
    @ObservationIgnored private var peer: MCPeerID?
    @ObservationIgnored private var session: MCSession?
    @ObservationIgnored private var advertiser: MCNearbyServiceAdvertiser?
    @ObservationIgnored private var browser: MCNearbyServiceBrowser?
    @ObservationIgnored private var tracker = SyncTracker()
    @ObservationIgnored private var applyingRemote = false
    @ObservationIgnored private var pendingSend: Task<Void, Never>?

    static var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: "householdSync") }
        set { UserDefaults.standard.set(newValue, forKey: "householdSync") }
    }

    static var savedCode: String {
        get { UserDefaults.standard.string(forKey: "householdCode") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "householdCode") }
    }

    func start(store: GroceryStore, name: String) {
        self.store = store
        let code = Self.savedCode
        guard Self.enabled, HouseholdCode.isValid(code) else { stop(); return }
        if isRunning, code == self.code { return }
        stop()
        self.code = code
        self.name = name.isEmpty ? "iPhone" : String(name.prefix(40))
        tracker = SyncTracker(items: store.items)

        let peer = MCPeerID(displayName: self.name)
        let session = MCSession(peer: peer, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        let info = ["tag": HouseholdCode.tag(for: code)]
        let advertiser = MCNearbyServiceAdvertiser(peer: peer, discoveryInfo: info, serviceType: Self.serviceType)
        advertiser.delegate = self
        let browser = MCNearbyServiceBrowser(peer: peer, serviceType: Self.serviceType)
        browser.delegate = self
        (self.peer, self.session, self.advertiser, self.browser) = (peer, session, advertiser, browser)
        advertiser.startAdvertisingPeer()
        browser.startBrowsingForPeers()
        isRunning = true
    }

    func stop() {
        pendingSend?.cancel()
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        session?.disconnect()
        (peer, session, advertiser, browser) = (nil, nil, nil, nil)
        connected = []
        isRunning = false
    }

    /// Called whenever the list changes here. Sends it shortly after, so a burst of edits goes as one.
    func itemsChanged() {
        guard let store else { return }
        if applyingRemote {
            tracker = SyncTracker(items: store.items)
            return
        }
        guard isRunning, !(session?.connectedPeers.isEmpty ?? true) else {
            tracker = SyncTracker(items: store.items)
            return
        }
        pendingSend?.cancel()
        pendingSend = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.sendChanges()
        }
    }

    @MainActor
    private func sendChanges() {
        guard let store else { return }
        let (removed, unchecked) = tracker.changes(in: store.items)
        send(store.makeSyncPacket(from: name, removed: removed, unchecked: unchecked))
    }

    private func send(_ packet: SyncPacket, to peers: [MCPeerID]? = nil) {
        guard let session, let data = try? packet.encoded() else { return }
        let targets = peers ?? session.connectedPeers
        guard !targets.isEmpty else { return }
        try? session.send(data, toPeers: targets, with: .reliable)
    }

    @MainActor
    private func receive(_ data: Data) {
        guard let store, let packet = SyncPacket.decode(data) else { return }
        applyingRemote = true
        store.applySyncPacket(packet)
        tracker = SyncTracker(items: store.items)
        applyingRemote = false
        lastReceived = Date()
    }

    @MainActor
    private func peersChanged() {
        connected = (session?.connectedPeers ?? []).map(\.displayName).sorted()
    }
}

extension HouseholdSync: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor in
            self.peersChanged()
            // A phone that just joined gets the whole list; it may have been offline for a while.
            if state == .connected, let store = self.store {
                self.send(store.makeSyncPacket(from: self.name), to: [peerID])
            }
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        Task { @MainActor in self.receive(data) }
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

extension HouseholdSync: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        guard let session, info?["tag"] == HouseholdCode.tag(for: code), !session.connectedPeers.contains(peerID) else { return }
        // Usually only one side invites, so two phones don't invite each other at once. With the same
        // name both do, which still connects.
        guard let me = peer, me.displayName >= peerID.displayName else { return }
        browser.invitePeer(peerID, to: session, withContext: Data(HouseholdCode.tag(for: code).utf8), timeout: 20)
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {}
}

extension HouseholdSync: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID,
                    withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        let matches = context.map { String(decoding: $0, as: UTF8.self) } == HouseholdCode.tag(for: code)
        invitationHandler(matches, matches ? session : nil)
    }
}

/// Turn on live syncing with others in the household and set the code you share with them.
struct HouseholdSyncView: View {
    @Environment(GroceryStore.self) private var store
    @Environment(HouseholdSync.self) private var sync
    @Environment(\.dismiss) private var dismiss
    @AppStorage("myName") private var myName = ""
    @State private var enabled = HouseholdSync.enabled
    @State private var code = HouseholdSync.savedCode

    private func apply() {
        HouseholdSync.enabled = enabled
        HouseholdSync.savedCode = code.trimmingCharacters(in: .whitespaces)
        sync.start(store: store, name: myName)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Sync with my household", isOn: $enabled)
                    TextField("Your name (shown to them)", text: $myName)
                } footer: {
                    Text("Phones with the same household code keep one list while the app is open on each, over your Wi-Fi or Bluetooth. Nothing goes through iCloud or any server.")
                }

                Section {
                    HStack {
                        TextField("Household code", text: $code)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button("New Code") { code = HouseholdCode.random() }
                            .buttonStyle(.borderless)
                    }
                    if !code.isEmpty && !HouseholdCode.isValid(code) {
                        Text("Use at least 4 letters or numbers.").font(.caption).foregroundStyle(.red)
                    }
                } header: {
                    Text("Household code")
                } footer: {
                    Text("Type the same code on each phone. Only phones with it can join, so pick one your neighbors won't guess.")
                }

                if enabled && sync.isRunning {
                    Section("Connected") {
                        if sync.connected.isEmpty {
                            HStack { ProgressView(); Text("Looking for phones nearby…").foregroundStyle(.secondary) }
                        }
                        ForEach(sync.connected, id: \.self) { Label($0, systemImage: "iphone") }
                        if let last = sync.lastReceived {
                            Text("Last update \(last.formatted(.relative(presentation: .named)))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    Text("New items, check-offs, un-checks and deletions are shared. Clearing done items on one phone doesn't bring them back on the other.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Live Sync")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onChange(of: enabled) { _, _ in apply() }
            .onChange(of: code) { _, _ in apply() }
            .onChange(of: myName) { _, _ in apply() }
        }
    }
}
