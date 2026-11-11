import SwiftUI

/// The app's four areas. The list is where you spend most of your time; the others gather what used to
/// sit in the list's More menu, each with a glance at what matters now.
struct RootView: View {
    @State private var tab = AppTab.list
    @Environment(GroceryStore.self) private var store
    @State private var showingWelcome = false

    var body: some View {
        TabView(selection: $tab) {
            Tab("List", systemImage: "checklist", value: AppTab.list) { ContentView(showList: { tab = .list }) }
            Tab("Meals", systemImage: "fork.knife", value: AppTab.meals) { MealsHub() }
            Tab("Kitchen", systemImage: "refrigerator", value: AppTab.kitchen) { KitchenHub() }
            Tab("Money", systemImage: "dollarsign.circle", value: AppTab.money) { MoneyHub() }
            Tab("Save Up", systemImage: "target", value: AppTab.saveUp) { SaveUpView() }
        }
        .onAppear {
            store.addOnlineStoreIfNeeded()
            showingWelcome = store.isFirstRun && !Storage.isUITesting
        }
        .sheet(isPresented: $showingWelcome) { WelcomeView() }
        // Last, so sheets presented from here pick up the brand color too.
        .tint(.brand)
    }
}

enum AppTab: String {
    case list, meals, kitchen, money, saveUp
}

/// The store the list is showing, for screens outside the list that add items to it.
private func currentShopID(_ store: GroceryStore) -> UUID? {
    let raw = UserDefaults.standard.string(forKey: "selectedShop") ?? ""
    if case .shop(let id) = ShopFilter(raw: raw), store.shop(for: id) != nil { return id }
    return nil
}

/// A row on a hub: an icon, a title, and a line about what's there now.
private struct HubRow: View {
    let title: String
    let systemImage: String
    let detail: String?
    var tint: Color = .accentColor
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(tint.gradient, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(.primary)
                    if let detail {
                        Text(detail).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(title)
    }
}

private func plural(_ count: Int, _ word: String) -> String {
    "\(count) \(word)\(count == 1 ? "" : "s")"
}

// MARK: Meals

struct MealsHub: View {
    @Environment(GroceryStore.self) private var store
    @State private var sheet: AppSheet?

    private var today: [Meal] {
        store.planned(on: Date()).compactMap { plan in store.meals.first { $0.id == plan.mealID } }
    }

    var body: some View {
        NavigationStack {
            List {
                if !today.isEmpty {
                    Section("Today") {
                        ForEach(today) { meal in
                            Label(meal.name.isEmpty ? "Untitled meal" : meal.name, systemImage: "calendar")
                        }
                    }
                }
                Section {
                    let cookable = store.mealsFromHome().count
                    HubRow(title: "What Can I Cook?", systemImage: "frying.pan",
                           detail: store.stock.isEmpty ? "Ideas from what's at home"
                               : cookable == 0 ? "Ideas from what's at home" : "\(plural(cookable, "meal")) use what's at home",
                           tint: .orange) { sheet = .cook }
                    HubRow(title: "Saved Meals", systemImage: "fork.knife",
                           detail: store.meals.isEmpty ? "Save a recipe or your list as a meal" : plural(store.meals.count, "meal"),
                           tint: .red) { sheet = .meals }
                    HubRow(title: "Company Coming", systemImage: "party.popper.fill",
                           detail: "Make-ahead meals that freeze well", tint: .pink) { sheet = .company }
                    let week = store.upcomingPlan().filter { $0.day < Date().addingTimeInterval(7 * 86_400) }.count
                    HubRow(title: "Meal Plan", systemImage: "calendar",
                           detail: week == 0 ? "Plan meals by day" : "\(week) planned this week",
                           tint: .purple) { sheet = .planner }
                }
            }
            .navigationTitle("Meals")
            .sheet(item: $sheet) { HubSheet(sheet: $0, shopID: currentShopID(store)) }
        }
    }
}

// MARK: Kitchen

/// "Use today", "Use tomorrow" or "Use in 3 days", counted in days the way At Home does.
private func useBy(_ date: Date, now: Date = Date()) -> String {
    let cal = Calendar.current
    let days = cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: date)).day ?? 0
    switch days {
    case ..<0: return "Use now"
    case 0: return "Use today"
    case 1: return "Use tomorrow"
    default: return "Use in \(days) days"
    }
}

struct KitchenHub: View {
    @Environment(GroceryStore.self) private var store
    @State private var sheet: AppSheet?

    var body: some View {
        NavigationStack {
            List {
                let soon = store.usingSoon()
                if !soon.isEmpty {
                    Section {
                        ForEach(soon.prefix(4)) { entry in
                            HStack {
                                Text(entry.name)
                                Spacer()
                                Text(useBy(entry.expires))
                                    .font(.subheadline).foregroundStyle(Color.brand)
                            }
                        }
                    } header: {
                        Text("Use soon")
                    }
                }
                Section {
                    HubRow(title: "At Home", systemImage: "refrigerator",
                           detail: store.stock.isEmpty ? "What you bought and when to use it"
                               : "\(plural(store.stock.count, "thing")), \(soon.count) to use soon",
                           tint: .teal) { sheet = .atHome }
                    HubRow(title: "Pantry Check", systemImage: "checklist",
                           detail: "Mark what you're out of", tint: .blue) { sheet = .pantry }
                    HubRow(title: "Usual & Buy Again", systemImage: "star",
                           detail: store.favorites.isEmpty ? "Staples you buy every time" : plural(store.favorites.count, "usual item"),
                           tint: .yellow) { sheet = .usual }
                }
            }
            .navigationTitle("Kitchen")
            .sheet(item: $sheet) { HubSheet(sheet: $0, shopID: currentShopID(store)) }
        }
    }
}

// MARK: Money

struct MoneyHub: View {
    @Environment(GroceryStore.self) private var store
    @State private var sheet: AppSheet?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    let spent = store.monthToDate()
                    VStack(alignment: .leading, spacing: 8) {
                        Text("This month").font(.subheadline).foregroundStyle(.secondary)
                        Text(Price.format(spent)).font(.largeTitle.weight(.semibold)).monospacedDigit()
                        if let budget = GroceryStore.monthlyBudget, budget > 0 {
                            ProgressView(value: min(spent, budget), total: budget)
                                .tint(spent > budget ? .red : (spent > budget * 0.8 ? .orange : .green))
                            Text("\(Price.format(max(budget - spent, 0))) left of \(Price.format(budget))")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .combine)
                }
                Section {
                    HubRow(title: "Spending", systemImage: "chart.bar",
                           detail: "By week, store and aisle", tint: .green) { sheet = .spending }
                    let deals = store.priceDeals().count
                    HubRow(title: "Price History", systemImage: "chart.line.uptrend.xyaxis",
                           detail: deals == 0 ? "What you've paid, and where it's cheapest" : "\(plural(deals, "good price")) right now",
                           tint: .mint) { sheet = .prices }
                    let totals = Totals(store.items.filter { !$0.isChecked })
                    HubRow(title: "Totals by Store", systemImage: "dollarsign.circle",
                           detail: totals.priced == 0 ? "What's on your list, by store" : "\(Price.format(totals.sum)) still to buy",
                           tint: .indigo) { sheet = .totals }
                    let saving = store.tripPlan().reduce(0) { $0 + $1.savings }
                    HubRow(title: "Plan the Trip", systemImage: "arrow.left.arrow.right",
                           detail: saving < 0.01 ? "Buy things where they're cheaper" : "Save \(Price.format(saving)) on today's trip",
                           tint: .orange) { sheet = .trip }
                    HubRow(title: "Scan Receipt", systemImage: "receipt",
                           detail: "Fill in prices from a photo", tint: .gray) { sheet = .receipt }
                }
            }
            .navigationTitle("Money")
            .sheet(item: $sheet) { HubSheet(sheet: $0, shopID: currentShopID(store)) }
        }
    }
}

/// The screens the hubs open.
private struct HubSheet: View {
    let sheet: AppSheet
    let shopID: UUID?

    var body: some View {
        switch sheet {
        case .cook: CookView(shopID: shopID)
        case .meals: MealsView(shopID: shopID, currentItems: [])
        case .planner: PlannerView(shopID: shopID)
        case .atHome: AtHomeView()
        case .pantry: PantryCheckView(shopID: shopID)
        case .usual: UsualView(shopID: shopID)
        case .spending: InsightsView()
        case .prices: PriceWatchView()
        case .totals: TotalsView()
        case .trip: TripPlanView()
        case .receipt: ReceiptView(shopID: shopID)
        case .company: CompanyComingView(shopID: shopID)
        default: EmptyView()
        }
    }
}

// MARK: Settings

/// Settings you set once: look, icon, allergies, stores, syncing and backups.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("theme") private var themeName = Theme.grey.rawValue
    @AppStorage("customColor") private var customHex = "34C759"
    @State private var sheet: AppSheet?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ThemePicker(selection: Binding(get: { Theme(rawValue: themeName) ?? .grey }, set: { themeName = $0.rawValue }),
                                custom: Binding(get: { Color(hex: customHex) },
                                                set: { customHex = $0.hex; themeName = Theme.custom.rawValue }))
                        .padding(.vertical, 6)
                } header: {
                    Text("List color")
                }
                Section {
                    HubRow(title: "App Icon", systemImage: "app", detail: nil, tint: .orange) { sheet = .icons }
                    HubRow(title: "Stores", systemImage: "storefront", detail: "Add stores and set their aisle order",
                           tint: .blue) { sheet = .shops }
                    HubRow(title: "Family Members", systemImage: "person.2.fill",
                           detail: "Who clothing is for", tint: .purple) { sheet = .people }
                    HubRow(title: "Registry People", systemImage: "gift.fill",
                           detail: "Who gifts are kept for", tint: .pink) { sheet = .registryPeople }
                    HubRow(title: "Custom Aisles", systemImage: "signpost.right.fill",
                           detail: "Your own sections beside the categories", tint: .indigo) { sheet = .aisles }
                    HubRow(title: "Allergies & Avoid List", systemImage: "exclamationmark.shield", detail: nil,
                           tint: .red) { sheet = .avoid }
                }
                Section {
                    HubRow(title: "iCloud Sync", systemImage: "icloud",
                           detail: CloudSync.enabled ? "On" : "Your lists on all your devices", tint: .blue) { sheet = .cloud }
                    HubRow(title: "Live Sync", systemImage: "arrow.triangle.2.circlepath",
                           detail: HouseholdSync.enabled ? "On" : "One list with your household", tint: .green) { sheet = .sync }
                    HubRow(title: "Back Up & Restore", systemImage: "externaldrive", detail: nil, tint: .gray) { sheet = .backup }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(item: $sheet) { sheet in
                switch sheet {
                case .icons: AppIconView()
                case .shops: ManageShopsView()
                case .avoid: AvoidListView()
                case .people: FamilyMembersView()
                case .aisles: CustomAislesView()
                case .registryPeople: RegistryPeopleView()
                case .sync: HouseholdSyncView()
                case .cloud: CloudSyncView()
                case .backup: BackupView()
                default: EmptyView()
                }
            }
        }
    }
}
