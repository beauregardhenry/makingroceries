import Foundation

extension GroceryStore {
    // MARK: Items

    func add(name: String, quantity: Int, aisle: Aisle, shopID: UUID? = nil, price: Double? = nil, note: String? = nil,
             sizeAmount: Double? = nil, sizeUnit: String? = nil, warning: String? = nil, barcode: String? = nil) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        // A known size carries over from the last time you bought it.
        let past = pastItem(named: trimmed)
        let (amount, unit) = sizeAmount != nil ? (sizeAmount, sizeUnit) : (past?.sizeAmount, past?.sizeUnit)
        var item = GroceryItem(name: trimmed, quantity: quantity, aisle: aisle, shopID: shopID, price: price, note: note)
        item.sizeAmount = amount
        item.sizeUnit = unit
        item.warning = warning
        items.append(item)
        remember(name: trimmed, aisle: aisle, shopID: shopID, price: price)
        if let i = history.firstIndex(where: { Self.same($0.name, trimmed) }) {
            if let amount, let unit { history[i].sizeAmount = amount; history[i].sizeUnit = unit }
            if let barcode { history[i].barcode = barcode }
        }
    }

    /// Adds an item, or raises the quantity of the same unchecked item already in that store.
    /// A missing aisle or price comes from history, then a keyword guess. With `inferShop`,
    /// a missing store comes from history too. Near-misses of a known name ("tomatos") are
    /// corrected to it.
    func addOrBump(name: String, quantity: Int = 1, aisle: Aisle? = nil, shopID: UUID?,
                   price: Double? = nil, inferShop: Bool = false, note: String? = nil) {
        let typed = name.trimmingCharacters(in: .whitespaces)
        guard !typed.isEmpty else { return }
        let trimmed = canonicalName(for: typed)
        let past = pastItem(named: trimmed)
        var shop = shopID
        if shop == nil, inferShop, let remembered = past?.shopID, self.shop(for: remembered) != nil {
            shop = remembered
        }
        if let i = items.firstIndex(where: { !$0.isChecked && $0.shopID == shop && Self.same($0.name, trimmed) }) {
            items[i].quantity += quantity
            return
        }
        let chosen = aisle ?? resolveAisle(for: trimmed)
        add(name: trimmed, quantity: quantity, aisle: chosen,
            shopID: shop, price: price ?? past?.price, note: note)
        // Nothing recognised it, so ask the on-device model, if this phone has one.
        if aisle == nil, past == nil, chosen == .other, AisleAI.isAvailable {
            Task { @MainActor in await refineAisle(forItemNamed: trimmed) }
        }
    }

    /// Files an item the keyword list couldn't place, using the on-device model, and remembers the answer.
    @MainActor
    func refineAisle(forItemNamed name: String) async {
        guard let guess = await AisleAI.aisle(for: name), guess != .other else { return }
        for i in items.indices where Self.same(items[i].name, name) && items[i].aisle == .other && !items[i].isChecked {
            items[i].aisle = guess
        }
        if let h = history.firstIndex(where: { Self.same($0.name, name) }), history[h].aisle == .other {
            history[h].aisle = guess
        }
    }

    func toggle(_ item: GroceryItem) {
        guard let i = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[i].isChecked.toggle()
        if items[i].isChecked {
            recordPurchase(of: items[i].name)
            recordCheckOff(items[i])
            recordStock(of: items[i])
        }
    }

    /// Notes where in the store an item was checked off, and updates the store's aisle order
    /// once enough trips agree.
    func recordCheckOff(_ item: GroceryItem, at date: Date = Date()) {
        guard let id = item.shopID, let i = shops.firstIndex(where: { $0.id == id }),
              shops[i].learnRoute != false else { return }
        var events = shops[i].routeEvents ?? []
        events.append(RouteEvent(aisle: item.aisle, date: date))
        shops[i].routeEvents = Array(events.suffix(RouteLearning.maximumEvents))
        if let learned = RouteLearning.order(current: shops[i].orderedAisles, events: shops[i].routeEvents ?? []) {
            shops[i].aisleOrder = learned
        }
    }

    /// Check-offs recorded for the route, for tests and the store screen.
    func tripCount(for shop: Shop) -> Int {
        RouteLearning.trips(from: shop.routeEvents ?? []).count
    }

    func delete(_ item: GroceryItem) {
        items.removeAll { $0.id == item.id }
        removePhotoIfUnused(item.photo)
    }

    func move(_ item: GroceryItem, to shopID: UUID?) {
        guard let i = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[i].shopID = shopID
    }

    func setPrice(_ price: Double?, for item: GroceryItem) {
        guard let i = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[i].price = price
        remember(name: item.name, aisle: item.aisle, shopID: item.shopID, price: price, countsAsUse: false)
    }

    /// Saves edits from the details screen.
    func update(_ item: GroceryItem) {
        guard let i = items.firstIndex(where: { $0.id == item.id }) else { return }
        let oldPhoto = items[i].photo
        items[i] = item
        if oldPhoto != item.photo { removePhotoIfUnused(oldPhoto) }
        remember(name: item.name, aisle: item.aisle, shopID: item.shopID, price: item.price, countsAsUse: false)
        if let h = history.firstIndex(where: { Self.same($0.name, item.name) }), let amount = item.sizeAmount, let unit = item.sizeUnit {
            history[h].sizeAmount = amount
            history[h].sizeUnit = unit
        }
    }

    /// Saves prices read from a receipt: sets the price of each matched list item and records every
    /// included price in the item's price history for `shopID`. Returns how many were saved.
    @discardableResult
    func applyReceipt(_ lines: [(entry: ReceiptEntry, item: GroceryItem?)], shopID: UUID?) -> Int {
        var saved = 0
        for line in lines {
            if let item = line.item, let i = items.firstIndex(where: { $0.id == item.id }) {
                items[i].price = line.entry.unitPrice
                remember(name: items[i].name, aisle: items[i].aisle, shopID: shopID ?? items[i].shopID,
                         price: line.entry.unitPrice, countsAsUse: false)
            } else {
                remember(name: line.entry.name, aisle: resolveAisle(for: line.entry.name), shopID: shopID,
                         price: line.entry.unitPrice, countsAsUse: false)
            }
            saved += 1
        }
        return saved
    }

    /// Clears checked items, limited to those `include` accepts (all by default).
    /// Returns what was removed so the caller can offer undo.
    @discardableResult
    func clearChecked(where include: (GroceryItem) -> Bool = { _ in true }) -> [ClearedItem] {
        let removed = items.enumerated().filter { $0.element.isChecked && include($0.element) }
            .map { ClearedItem(index: $0.offset, item: $0.element) }
        let ids = Set(removed.map(\.item.id))
        items.removeAll { ids.contains($0.id) }
        return removed
    }

    /// Puts cleared items back where they were.
    func restore(_ cleared: [ClearedItem]) {
        var restored = items
        for entry in cleared.sorted(by: { $0.index < $1.index }) {
            restored.insert(entry.item, at: min(entry.index, restored.count))
        }
        items = restored
    }

    func isOnList(_ name: String) -> Bool {
        items.contains { !$0.isChecked && Self.same($0.name, name) }
    }

    /// Unchecked items for a widget or Siri: one store's, in its walking order, or everything.
    func widgetItems(shopID: UUID?) -> [GroceryItem] {
        let shop = shop(for: shopID)
        let pool = items.filter { !$0.isChecked && (shopID == nil || $0.shopID == shopID) }
        let order = shop?.orderedAisles ?? Aisle.allCases
        return pool.sorted { (order.firstIndex(of: $0.aisle) ?? 0) < (order.firstIndex(of: $1.aisle) ?? 0) }
    }

    func removePhotoIfUnused(_ name: String?) {
        guard let name, !items.contains(where: { $0.photo == name }) else { return }
        try? FileManager.default.removeItem(at: Storage.photos.appending(path: name))
    }
}
