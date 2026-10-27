import Foundation

/// Which store you're probably at, shared between the app and the widget. The app writes it when you
/// arrive somewhere or open the app near a store; it goes stale after a few hours.
enum NearbyStore {
    private static let defaults = UserDefaults(suiteName: Storage.groupID) ?? .standard
    private static let idKey = "nearbyShopID"
    private static let dateKey = "nearbyShopDate"
    static let lifetime: TimeInterval = 3 * 3600

    static func record(_ id: UUID?) {
        if let id {
            defaults.set(id.uuidString, forKey: idKey)
            defaults.set(Date(), forKey: dateKey)
        } else {
            defaults.removeObject(forKey: idKey)
        }
    }

    /// The store you were last near, if that was recent and the store still exists.
    static func currentShopID(among shops: [Shop], now: Date = Date()) -> UUID? {
        guard let raw = defaults.string(forKey: idKey), let id = UUID(uuidString: raw),
              let date = defaults.object(forKey: dateKey) as? Date, now.timeIntervalSince(date) < lifetime,
              shops.contains(where: { $0.id == id }) else { return nil }
        return id
    }

    /// The closest store with a saved location, within `radius` meters of the given point.
    static func nearest(to latitude: Double, _ longitude: Double, among shops: [Shop], radius: Double = 400) -> Shop? {
        func meters(_ s: Shop) -> Double? {
            guard let la = s.latitude, let lo = s.longitude else { return nil }
            // Equirectangular approximation, accurate to a few meters over a few hundred meters.
            let dLat = (la - latitude) * 111_320
            let dLon = (lo - longitude) * 111_320 * cos(latitude * .pi / 180)
            return (dLat * dLat + dLon * dLon).squareRoot()
        }
        return shops.compactMap { shop in meters(shop).map { (shop, $0) } }
            .filter { $0.1 <= radius }
            .min { $0.1 < $1.1 }?.0
    }
}
