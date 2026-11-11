import CoreSpotlight
import SwiftUI

struct ContentView: View {
    @Environment(GroceryStore.self) private var store
    /// Brings the list tab forward, for a control or Spotlight result opened from another tab.
    var showList: () -> Void = {}
    @State private var sheet: AppSheet?
    @State private var detailItem: GroceryItem?
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("shoppingMode") private var shoppingMode = false
    @State private var clearedBatch: ClearedBatch?
    @State private var pricingItem: GroceryItem?
    @State private var priceText = ""
    /// Changes when a control asks for the quick-add bar, which then takes focus.
    @State private var quickAddRequest = 0
    /// Text to put in the quick-add bar with that request, such as a name tapped in Spotlight.
    @State private var quickAddPrefill = ""
    /// In Shopping Mode, whether the In the cart section is open. Closed keeps the screen on what's left.
    @State private var cartExpanded = false
    @AppStorage("selectedShop") private var selectedShopRaw = ""
    @AppStorage("theme") private var themeName = Theme.grey.rawValue
    @AppStorage("customColor") private var customHex = "34C759"

    private var theme: Binding<Theme> {
        Binding(get: { Theme(rawValue: themeName) ?? .grey }, set: { themeName = $0.rawValue })
    }

    private var customColor: Binding<Color> {
        Binding(get: { Color(hex: customHex) },
                set: { customHex = $0.hex; themeName = Theme.custom.rawValue })
    }

    /// Colors sit on top of light mode, so the tint is the same strength for all of them.
    private let tintOpacity = 0.22

    /// The chosen filter; falls back to "All" when the chosen store was deleted.
    private var filter: ShopFilter {
        let filter = ShopFilter(raw: selectedShopRaw)
        if case .shop(let id) = filter, !store.shops.contains(where: { $0.id == id }) { return .all }
        return filter
    }

    private var selectedShop: Binding<ShopFilter> {
        Binding(get: { filter }, set: { selectedShopRaw = $0.raw })
    }

    private func isVisible(_ item: GroceryItem) -> Bool {
        switch filter {
        case .travel: item.forTravel
        case .clothing: item.forClothing
        case .registry: item.forRegistry
        case .all: !item.isSeparate
        case .shop(let id): !item.isSeparate && item.shopID == id
        }
    }

    private var visibleItems: [GroceryItem] {
        store.items.filter(isVisible)
    }

    /// The store new items start in: the chosen one, otherwise none.
    private var newItemShopID: UUID? {
        if case .shop(let id) = filter { return id }
        return nil
    }

    /// Under the title: what's left, and what it will cost once something is priced. Checked items are
    /// already in the cart, so they don't count, which matches "still to buy" on the Money tab.
    private var subtitle: String {
        let remaining = visibleItems.filter { !$0.isChecked }
        let left = remaining.count
        let totals = Totals(remaining)
        let leftText = left == 0 ? (visibleItems.isEmpty ? "" : "All done") : "\(left) left"
        guard totals.priced > 0 else { return leftText }
        let total = Price.format(totals.sum) + (totals.priced < totals.count ? " so far" : "")
        return leftText.isEmpty ? total : "\(leftText) · \(total)"
    }

    /// Under the list: what everything on screen adds up to, and across all lists when one is picked.
    private var runningTotal: RunningTotal {
        RunningTotal(visible: visibleItems, everyday: store.items.filter { !$0.isSeparate })
    }

    private var navigationTitle: String {
        switch filter {
        case .all: "Groceries"
        case .travel: "Travel"
        case .clothing: "Clothing"
        case .registry: "Registry"
        case .shop(let id): store.shopName(for: id) ?? "Groceries"
        }
    }

    /// The store whose aisle map applies, when one store is selected.
    private var mappedShop: Shop? {
        if case .shop(let id) = filter { return store.shop(for: id) }
        return nil
    }

    /// Sections follow the selected store's walking order, or the default order otherwise.
    private var sections: [(section: AisleSection, items: [GroceryItem])] {
        store.sectionGroups(visibleItems, shop: mappedShop)
    }

    private var customTints: [Color] { [.indigo, .mint, .brown, .cyan, .orange, .teal] }

    /// A section's header: a built-in category keeps its icon and color, your own aisles get a sign.
    private func makeSection(_ section: AisleSection, _ items: [GroceryItem]) -> DisplaySection {
        switch section {
        case .aisle(let aisle):
            return DisplaySection(id: aisle.rawValue, title: aisle.rawValue, symbol: aisle.symbol, aisle: aisle,
                                  label: mappedShop?.label(for: aisle), items: items)
        case .custom(let id):
            let index = store.customAisles.firstIndex { $0.id == id } ?? 0
            return DisplaySection(id: section.id, title: store.customAisle(for: id)?.name ?? "Aisle",
                                  symbol: "signpost.right.fill", aisle: nil,
                                  tint: customTints[index % customTints.count], label: nil, items: items)
        }
    }

    /// How many aisles on screen have everything checked off, for the finished-an-aisle buzz.
    private var finishedAisles: Int {
        Dictionary(grouping: visibleItems, by: \.aisle).values.filter { $0.allSatisfy(\.isChecked) }.count
    }

    private var remainingCount: Int { visibleItems.filter { !$0.isChecked }.count }

    private var shoppingProgress: ShoppingProgress {
        ShoppingProgress(items: visibleItems, order: mappedShop?.orderedAisles ?? Aisle.allCases,
                         label: { mappedShop?.label(for: $0) })
    }

    /// Ends a trip: what's in the cart comes off the list (with Undo), and the list goes back to normal.
    private func finishShopping() {
        clearDone()
        withAnimation { shoppingMode = false }
        cartExpanded = false
    }

    /// Keeps the screen on while shopping, so it doesn't lock between aisles.
    private func updateIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = shoppingMode && scenePhase == .active
    }

    /// Changes whenever the Live Activity needs to be brought up to date.
    private var activityKey: String { "\(shoppingMode)|\(selectedShopRaw)|\(remainingCount)|\(visibleItems.count)" }

    private func syncShoppingActivity() {
        #if os(iOS)
        let next = displaySections.lazy.flatMap(\.items).first { !$0.isChecked }?.name
        let (remaining, total, name, active) = (remainingCount, visibleItems.count, navigationTitle, shoppingMode)
        Task { await ShoppingActivity.sync(storeName: name, remaining: remaining, total: total, next: next, active: active) }
        #endif
    }

    private struct DisplaySection: Identifiable {
        let id: String
        let title: String
        let symbol: String
        var aisle: Aisle?
        /// Overrides the aisle's color, for a person's header.
        var tint: Color?
        let label: String?
        let items: [GroceryItem]
    }

    /// Normal view: by aisle. Shopping mode: what's still needed by aisle, then what's in the cart.
    private var displaySections: [DisplaySection] {
        if filter == .clothing { return clothingDisplaySections }
        if filter == .registry { return registryDisplaySections }
        guard shoppingMode else { return sections.map { makeSection($0.section, $0.items) } }
        var result = store.sectionGroups(visibleItems.filter { !$0.isChecked }, shop: mappedShop)
            .map { makeSection($0.section, $0.items) }
        let cart = visibleItems.filter(\.isChecked)
        if !cart.isEmpty {
            result.append(DisplaySection(id: "cart", title: "In the cart", symbol: "cart.fill", label: nil, items: cart))
        }
        return result
    }

    private static let personColors: [Color] = [.blue, .pink, .green, .orange, .purple, .teal, .red, .indigo]

    /// Clothing: a header for each person, in the order of your family list.
    private var clothingDisplaySections: [DisplaySection] {
        store.clothingSections(visibleItems).map { group in
            if let person = group.person {
                let index = store.people.firstIndex { $0.id == person.id } ?? 0
                return DisplaySection(id: "person-\(person.id)", title: person.name, symbol: "person.fill", aisle: nil,
                                      tint: Self.personColors[index % Self.personColors.count], label: nil, items: group.items)
            }
            return DisplaySection(id: "person-none", title: "No one yet", symbol: "person.crop.circle.badge.questionmark",
                                  aisle: nil, tint: .gray, label: nil, items: group.items)
        }
    }

    /// Registry: a header for each person, with their birthday, in the order of your registry list.
    private var registryDisplaySections: [DisplaySection] {
        store.registrySections(visibleItems).map { group in
            if let person = group.person {
                let index = store.registryPeople.firstIndex { $0.id == person.id } ?? 0
                return DisplaySection(id: "gift-\(person.id)", title: person.name, symbol: "gift.fill", aisle: nil,
                                      tint: Self.personColors[index % Self.personColors.count],
                                      label: RegistryInfo.birthdayText(person), items: group.items)
            }
            return DisplaySection(id: "gift-none", title: "Not assigned yet", symbol: "gift", aisle: nil, tint: .gray,
                                  label: nil, items: group.items)
        }
    }

    /// The visible list as plain text, grouped by aisle in walking order, for sharing.
    private var shareText: String {
        if filter == .registry {
            return RegistryInfo.shareText(gifts: visibleItems, sections: store.registrySections(visibleItems))
        }
        var lines = [filter == .all ? "Grocery list" : "\(navigationTitle) list"]
        for (section, items) in sections {
            let made = makeSection(section, items)
            var header = made.title
            if let label = made.label { header += " (\(label))" }
            lines += ["", header]
            for item in items {
                var line = "\(item.isChecked ? "☑" : "☐") \(item.name)"
                if item.quantity > 1 { line += " ×\(item.quantity)" }
                if filter == .all, let shop = store.shopName(for: item.shopID) { line += " (\(shop))" }
                lines.append(line)
            }
        }
        let totals = Totals(visibleItems)
        if totals.priced > 0 { lines += ["", "Total: \(Price.format(totals.sum))"] }
        return lines.joined(separator: "\n")
    }

    private func clearDone() {
        let removed = store.clearChecked(where: isVisible)
        guard !removed.isEmpty else { return }
        withAnimation { clearedBatch = ClearedBatch(items: removed) }
    }

    /// Does what a Control Center, Lock Screen or Action button control opened the app for.
    private func handlePendingAction() {
        let action = PendingAction.take()
        if action != nil { showList() }
        switch action {
        case .quickAdd:
            sheet = nil
            quickAddPrefill = ""
            quickAddRequest += 1
        case .startShopping:
            sheet = nil
            if let id = NearbyStore.currentShopID(among: store.shops) { selectedShopRaw = ShopFilter.shop(id).raw }
            shoppingMode = true
        case nil:
            break
        }
    }

    /// Opens what was tapped in Spotlight: the item's details, the meals, or the list ready to add it.
    private func openSpotlightResult(_ activity: NSUserActivity) {
        guard let id = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
              let (kind, key) = SpotlightEntry.parse(id) else { return }
        sheet = nil
        showList()
        switch kind {
        case .item:
            if let item = store.items.first(where: { $0.id.uuidString == key }) {
                selectedShopRaw = ""
                detailItem = item
            }
        case .meal:
            sheet = .meals
        case .past:
            selectedShopRaw = ""
            quickAddPrefill = key
            quickAddRequest += 1
        }
    }

    private func beginPricing(_ item: GroceryItem) {
        priceText = Price.editText(item.price)
        pricingItem = item
    }

    @ViewBuilder
    private func sheetView(_ sheet: AppSheet) -> some View {
        switch sheet {
        case .add: AddItemView(shopID: newItemShopID, travel: filter == .travel, clothing: filter == .clothing,
                                  registry: filter == .registry)
        case .shops: ManageShopsView()
        case .usual: UsualView(shopID: newItemShopID)
        case .meals: MealsView(shopID: newItemShopID, currentItems: visibleItems)
        case .totals: TotalsView()
        case .pantry: PantryCheckView(shopID: newItemShopID)
        case .backup: BackupView()
        case .receipt: ReceiptView(shopID: newItemShopID)
        case .trip: TripPlanView()
        case .planner: PlannerView(shopID: newItemShopID)
        case .scan: ScanCheckOffView(shopID: newItemShopID)
        case .spending: InsightsView()
        case .atHome: AtHomeView()
        case .avoid: AvoidListView()
        case .icons: AppIconView()
        case .send: SendListView(shopID: newItemShopID)
        case .cook: CookView(shopID: newItemShopID)
        case .prices: PriceWatchView()
        case .sync: HouseholdSyncView()
        case .cloud: CloudSyncView()
        case .settings: SettingsView()
        case .company: CompanyComingView(shopID: newItemShopID)
        case .people: FamilyMembersView()
        case .aisles: CustomAislesView()
        case .registryPeople: RegistryPeopleView()
        }
    }

    @ViewBuilder
    private func sectionView(_ section: DisplaySection) -> some View {
        let isCart = shoppingMode && section.id == "cart"
        Section {
            if !isCart || cartExpanded {
                ForEach(section.items) { item in
                    ItemRow(item: item, showShop: filter == .all, large: shoppingMode,
                            onSetPrice: beginPricing, onEdit: { detailItem = $0 })
                }
                .onDelete { offsets in
                    offsets.map { section.items[$0] }.forEach(store.delete)
                }
            }
        } header: {
            if isCart {
                cartHeader(count: section.items.count)
            } else {
                aisleHeader(section)
            }
        }
    }

    private func cartHeader(count: Int) -> some View {
        Button {
            withAnimation { cartExpanded.toggle() }
        } label: {
            HStack {
                Label("In the cart (\(count))", systemImage: "cart.fill")
                Spacer()
                Image(systemName: "chevron.right")
                    .rotationEffect(.degrees(cartExpanded ? 90 : 0))
                    .accessibilityHidden(true)
            }
            .font(.headline)
            .tintedBand(.green)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(cartExpanded ? "Hides what's in the cart" : "Shows what's in the cart")
    }

    private func aisleHeader(_ section: DisplaySection) -> some View {
        HStack(spacing: 10) {
            if let aisle = section.aisle {
                AisleBadge(aisle: aisle, size: shoppingMode ? 28 : 24)
                Text(section.title)
            } else {
                Label(section.title, systemImage: section.symbol)
            }
            Spacer()
            if let label = section.label {
                Text(label).textCase(nil).font(.subheadline.weight(.semibold))
            }
        }
        .font((shoppingMode ? Font.headline : Font.subheadline).weight(.bold))
        .tintedBand(section.tint ?? section.aisle?.tint ?? .gray)
    }

    private var finishSection: some View {
        Section {
            Button(action: finishShopping) {
                Label("Finish Shopping", systemImage: "checkmark.circle.fill")
                    .font(.title3.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        } footer: {
            Text("Takes what's in the cart off your list. You can undo it.")
                .frame(maxWidth: .infinity)
        }
    }

    private var topBar: some View {
        VStack(spacing: 0) {
            ShopBar(selection: selectedShop) { sheet = .shops }
            if shoppingMode && !visibleItems.isEmpty {
                ShoppingHeader(progress: shoppingProgress)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 8) {
            if let batch = clearedBatch {
                UndoBanner(count: batch.items.count) {
                    withAnimation {
                        store.restore(batch.items)
                        clearedBatch = nil
                    }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if runningTotal.pricedCount > 0 { RunningTotalBar(total: runningTotal) }
            QuickAddBar(shopID: newItemShopID, inferShop: filter == .all, travel: filter == .travel, clothing: filter == .clothing, registry: filter == .registry, focusRequest: quickAddRequest, prefill: quickAddPrefill,
                        showsDue: !shoppingMode)
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
    }

    @ToolbarContentBuilder
    private var listToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if shoppingMode {
                Button("Done Shopping", action: finishShopping)
            } else {
                Button("Clear Done", action: clearDone)
                    .disabled(!visibleItems.contains(where: \.isChecked))
            }
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            Menu {
                Toggle(isOn: $shoppingMode) {
                    Label("Shopping Mode", systemImage: "textformat.size")
                }
                Button("Scan to Check Off", systemImage: "barcode.viewfinder") { sheet = .scan }
                Divider()
                Button("Send List to Family", systemImage: "person.2") { sheet = .send }
                Button("Family Members", systemImage: "person.crop.circle.badge.plus") { sheet = .people }
                Button("Custom Aisles", systemImage: "signpost.right") { sheet = .aisles }
                Button("Registry People", systemImage: "gift") { sheet = .registryPeople }
                ShareLink(item: shareText) {
                    Label("Share List as Text", systemImage: "square.and.arrow.up")
                }
                .disabled(visibleItems.isEmpty)
                Divider()
                Button("Settings", systemImage: "gearshape") { sheet = .settings }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel("More")
            Button("Add", systemImage: "plus") { sheet = .add }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(displaySections) { section in
                    sectionView(section)
                }
                if shoppingMode && shoppingProgress.isDone {
                    finishSection
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) { topBar }
            .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
            .task(id: clearedBatch?.id) {
                guard let id = clearedBatch?.id else { return }
                try? await Task.sleep(for: .seconds(7))
                if clearedBatch?.id == id { withAnimation { clearedBatch = nil } }
            }
            .scrollContentBackground(.hidden)
            .background {
                Color(.systemGroupedBackground)
                    .overlay(theme.wrappedValue.tint(custom: customColor.wrappedValue).opacity(tintOpacity))
                    .ignoresSafeArea()
            }
            .animation(.default, value: themeName + customHex)
            .overlay {
                if visibleItems.isEmpty {
                    ContentUnavailableView("Your list is empty", systemImage: "cart",
                                           description: Text(filter == .all
                                                             ? "Tap + to add your first item."
                                                             : filter == .clothing
                                                             ? "Tap + to add clothing for someone. Add your family under ⋯ › Family Members."
                                                             : filter == .registry
                                                             ? "Tap + to add a gift idea. Add the people you buy for under ⋯ › Registry People."
                                                             : "Tap + to add something here."))
                }
            }
            .navigationTitle(navigationTitle)
            .navigationSubtitle(subtitle)
            .toolbar { listToolbar }
            .sheet(item: $sheet) { sheetView($0) }
            .sheet(item: $detailItem) { item in
                ItemDetailView(item: item, repeatDays: store.recurrence(for: item)?.everyDays ?? 0)
            }
            .onChange(of: scenePhase) { _, phase in
                updateIdleTimer()
                if phase == .active {
                    handlePendingAction()
                    store.reload()
                    Task { await ArrivalReminders.shared.refreshNearestStore(among: store.shops) }
                }
            }
            .onAppear {
                handlePendingAction()
                updateIdleTimer()
            }
            .onChange(of: shoppingMode) { _, _ in updateIdleTimer() }
            .onContinueUserActivity(CSSearchableItemActionType, perform: openSpotlightResult)
            .onReceive(NotificationCenter.default.publisher(for: PendingAction.requested)) { _ in handlePendingAction() }
            .modifier(ShoppingFeedback(finishedAisles: finishedAisles, key: activityKey, sync: syncShoppingActivity))
            .alert("Some Saved Data Couldn't Be Read", isPresented: Binding(
                get: { !store.loadProblems.isEmpty },
                set: { if !$0 { store.loadProblems = [] } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("A copy of \(LoadProblem.describe(store.loadProblems)) was kept in the app's Recovered folder before anything was saved over it. Everything else loaded normally.")
            }
            .alert("Set Price", isPresented: Binding(get: { pricingItem != nil },
                                                     set: { if !$0 { pricingItem = nil } }),
                   presenting: pricingItem) { item in
                TextField("0.00", text: $priceText).keyboardType(.decimalPad)
                Button("Save") { store.setPrice(Price.parse(priceText), for: item) }
                Button("Remove Price", role: .destructive) { store.setPrice(nil, for: item) }
                Button("Cancel", role: .cancel) {}
            } message: { item in
                Text("Price of one \(item.name)")
            }
        }
        .preferredColorScheme(theme.wrappedValue.scheme)
    }
}

enum LoadProblem {
    private static let names = [
        "grocery": "your list", "shops": "your stores", "favorites": "your usual items", "meals": "your meals",
        "history": "your item history", "recurring": "your repeating items", "plan": "your meal plan",
        "stock": "what's at home", "spending": "your spending",
    ]

    static func describe(_ files: [String]) -> String {
        files.map { names[$0] ?? $0 }.formatted(.list(type: .and))
    }
}

/// Every sheet the main screen can show; one at a time.
enum AppSheet: String, Identifiable {
    case add, people, aisles, registryPeople, company, shops, usual, meals, totals, pantry, backup, receipt, trip, planner, scan, spending, atHome, avoid, icons, send, cook, prices, sync, settings, cloud
    var id: String { rawValue }
}

struct ItemRow: View {
    @Environment(GroceryStore.self) private var store
    let item: GroceryItem
    var showShop = false
    /// Shopping mode: bigger text and tap targets.
    var large = false
    var onSetPrice: (GroceryItem) -> Void = { _ in }
    var onEdit: (GroceryItem) -> Void = { _ in }

    /// Second line: the store (when listing every store) and the unit price.
    private var detail: String? {
        var parts: [String] = []
        if showShop, let shop = store.shopName(for: item.shopID) { parts.append(shop) }
        if let price = item.price, item.quantity > 1 { parts.append("\(Price.format(price)) each") }
        if let unit = item.unitPriceText { parts.append(unit) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var spokenSummary: String {
        var parts = [item.name]
        if item.quantity > 1 { parts.append("quantity \(item.quantity)") }
        if let shop = store.shopName(for: item.shopID), showShop { parts.append(shop) }
        if let line = item.lineTotal { parts.append(Price.format(line)) }
        if let note = item.note { parts.append(note) }
        if let warning = item.warning { parts.append("Warning: \(warning)") }
        parts.append(item.isChecked ? "bought" : "needed")
        return parts.joined(separator: ", ")
    }

    var body: some View {
        Button {
            withAnimation { store.toggle(item) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(item.isChecked ? .green : .secondary)
                    .font(large ? .largeTitle : .title3)
                if let photo = item.photo {
                    ItemThumbnail(name: photo, size: large ? 52 : 40)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(large ? .title2.weight(.medium) : .body)
                        .strikethrough(item.isChecked)
                        .foregroundStyle(item.isChecked ? .secondary : .primary)
                    if !large, let detail {
                        Text(detail).font(.caption).foregroundStyle(.secondary)
                    }
                    if let note = item.note {
                        Text(note).font(large ? .subheadline : .caption).italic().foregroundStyle(.secondary)
                    }
                    if let warning = item.warning {
                        Label(warning, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption.weight(.semibold)).foregroundStyle(Color.brand)
                    }
                    if !large, !item.isChecked, let hint = store.priceHint(for: item) {
                        Text(hint).font(.caption).foregroundStyle(Color.positive)
                    }
                }
                Spacer()
                if item.quantity > 1 {
                    Text("×\(item.quantity)").foregroundStyle(.secondary).monospacedDigit()
                        .font(large ? .title2.weight(.semibold) : .body)
                }
                if !large, let line = item.lineTotal {
                    Text(Price.format(line)).monospacedDigit()
                        .foregroundStyle(item.isChecked ? .secondary : .primary)
                }
            }
            .padding(.vertical, large ? 10 : 0)
            // A plain button only reacts to its text and icons; make the blank middle of the row tappable too.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .light), trigger: item.isChecked)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spokenSummary)
        .accessibilityIdentifier("item-\(item.name)")
        .accessibilityHint(item.isChecked ? "Double tap to put it back on the list" : "Double tap to mark it bought")
        .accessibilityAction(named: "Edit details") { onEdit(item) }
        .accessibilityAction(named: "Set price") { onSetPrice(item) }
        .accessibilityAction(named: "Delete") { store.delete(item) }
        .contextMenu {
            if item.forRegistry {
                ForEach(Array(RegistryInfo.lines(for: item).enumerated()), id: \.offset) { index, line in
                    Button(line, systemImage: index == 0 ? "calendar" : "gift") {}.disabled(true)
                }
                Divider()
            }
            if item.forClothing {
                // When it was added and its size, shown only here and never on the row.
                ForEach(Array(ClothingInfo.lines(for: item).enumerated()), id: \.offset) { index, line in
                    Button(line, systemImage: index == 0 ? "calendar" : "ruler") {}.disabled(true)
                }
                Divider()
            }
            Button("Edit Details…", systemImage: "pencil") { onEdit(item) }
            Button("Set Price…", systemImage: "dollarsign.circle") { onSetPrice(item) }
            Button("Add to Usual", systemImage: "star") {
                store.addFavorite(name: item.name, quantity: item.quantity, aisle: item.aisle)
            }
            if item.forRegistry {
                Menu("Move to Person", systemImage: "gift") {
                    ForEach(store.registryPeople) { person in
                        Button(person.name) { store.move(item, toGiftFor: person.id) }
                    }
                    Button("Not assigned yet") { store.move(item, toGiftFor: nil) }
                }
            } else if item.forClothing {
                Menu("Move to Person", systemImage: "person.crop.circle") {
                    ForEach(store.people) { person in
                        Button(person.name) { store.move(item, toPerson: person.id) }
                    }
                    Button("No one yet") { store.move(item, toPerson: nil) }
                }
            } else {
                Menu("Move to Store", systemImage: "arrow.right.circle") {
                    ForEach(store.shops) { shop in
                        Button(shop.name) { store.move(item, to: shop.id) }
                    }
                    Button(Shop.noStoreName) { store.move(item, to: nil) }
                }
            }
            Button("Delete", systemImage: "trash", role: .destructive) { store.delete(item) }
        }
    }
}

struct AddItemView: View {
    @Environment(GroceryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var quantity = 1
    @State private var aisle: Aisle = .produce
    @State private var customAisleID: UUID?
    @State private var shopID: UUID?
    @State private var priceText = ""
    @State private var showingScanner = false
    @State private var lookupMessage: String?
    @State private var isLookingUp = false
    @State private var travel = false
    /// Adding clothing: pick who it's for and its size instead of an aisle and store.
    let clothing: Bool
    /// Adding a gift: pick who it is for and the occasion.
    let registry: Bool
    @State private var giftForID: UUID?
    @State private var occasion = ""
    @State private var personID: UUID?
    @State private var sizeText = ""

    init(shopID: UUID?, travel: Bool = false, clothing: Bool = false, registry: Bool = false) {
        _shopID = State(initialValue: shopID)
        _travel = State(initialValue: travel)
        self.clothing = clothing
        self.registry = registry
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Item name", text: $name).textInputAutocapitalization(.words)
                Button("Scan Barcode", systemImage: "barcode.viewfinder") { showingScanner = true }
                if isLookingUp {
                    HStack { ProgressView(); Text("Looking up product…").foregroundStyle(.secondary) }
                } else if let lookupMessage {
                    Text(lookupMessage).font(.footnote).foregroundStyle(.secondary)
                }
                Stepper("Quantity: \(quantity)", value: $quantity, in: 1...99)
                TextField("Price (optional)", text: $priceText).keyboardType(.decimalPad)
                if registry {
                    Picker("For", selection: $giftForID) {
                        Text("Not assigned yet").tag(UUID?.none)
                        ForEach(store.registryPeople) { Text($0.name).tag(UUID?.some($0.id)) }
                    }
                    Picker("Occasion", selection: $occasion) {
                        Text("None").tag("")
                        ForEach(RegistryOccasion.all, id: \.self) { Text($0).tag($0) }
                    }
                } else if clothing {
                    Picker("For", selection: $personID) {
                        Text("No one yet").tag(UUID?.none)
                        ForEach(store.people) { Text($0.name).tag(UUID?.some($0.id)) }
                    }
                    LabeledContent("Size") {
                        TextField(store.lastSize(for: personID, itemNamed: name).map { "Last: \($0)" } ?? "M, 8, 10 Kids, 32x30",
                                  text: $sizeText)
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.never)
                    }
                } else {
                    Picker("Category", selection: $aisle) {
                        ForEach(Aisle.allCases) { Label($0.rawValue, systemImage: $0.symbol).tag($0) }
                    }
                    if !store.customAisles.isEmpty {
                        Picker("Aisle", selection: $customAisleID) {
                            Text("None").tag(UUID?.none)
                            ForEach(store.customAisles) { Text($0.name).tag(UUID?.some($0.id)) }
                        }
                    }
                    Picker("Store", selection: $shopID) {
                        Text(Shop.noStoreName).tag(UUID?.none)
                        ForEach(store.shops) { Text($0.name).tag(UUID?.some($0.id)) }
                    }
                    Toggle("For a trip", isOn: $travel)
                }
            }
            .navigationTitle("New Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        store.add(name: name, quantity: quantity, aisle: aisle, shopID: (clothing || registry) ? nil : shopID, price: Price.parse(priceText),
                                  travel: (clothing || registry) ? false : travel, clothing: clothing, personID: personID, clothingSize: sizeText,
                                  customAisleID: customAisleID, registry: registry, giftForID: giftForID, occasion: occasion)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .sheet(isPresented: $showingScanner) {
            ScanSheet { code in Task { await lookUp(code) } }
        }
    }

    private func lookUp(_ code: String) async {
        isLookingUp = true
        lookupMessage = nil
        defer { isLookingUp = false }
        do {
            if let product = try await ProductLookup.product(for: code) {
                let size = product.size.flatMap(SizeParser.parse)
                let warning = AvoidList.message(AvoidList.warnings(allergens: product.allergens, ingredients: product.ingredients,
                                                                    avoid: AvoidList.words))
                store.add(name: product.name, quantity: quantity, aisle: product.aisle ?? aisle, shopID: shopID,
                          price: Price.parse(priceText), sizeAmount: size?.amount, sizeUnit: size?.unit,
                          warning: warning, barcode: code, travel: travel, clothing: clothing, personID: personID,
                          customAisleID: customAisleID)
                if let warning {
                    // Don't hide a warning by closing the sheet.
                    lookupMessage = "Added \(product.name). Warning: \(warning)."
                    name = ""
                } else {
                    dismiss()
                }
            } else {
                lookupMessage = "No product found for \(code). Type the name instead."
            }
        } catch {
            lookupMessage = "Couldn't look up that barcode. Check your connection."
        }
    }
}

/// What Clear Done removed, kept briefly so it can be undone.
struct ClearedBatch: Identifiable {
    let id = UUID()
    let items: [ClearedItem]
}

struct UndoBanner: View {
    let count: Int
    let onUndo: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            Text("Cleared \(count) item\(count == 1 ? "" : "s")")
            Spacer()
            Button("Undo", action: onUndo).fontWeight(.semibold)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
    }
}

/// The finished-an-aisle buzz, and keeping the lock screen Live Activity current.
private struct ShoppingFeedback: ViewModifier {
    let finishedAisles: Int
    let key: String
    let sync: () -> Void

    func body(content: Content) -> some View {
        content
            .sensoryFeedback(trigger: finishedAisles) { old, new in new > old ? .success : nil }
            .onChange(of: key) { _, _ in sync() }
    }
}
