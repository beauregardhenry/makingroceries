import CoreLocation
import UserNotifications

/// Notifies you when you arrive at a store that has items on its list.
/// Locations stay on the device; nothing is sent anywhere.
@MainActor
final class ArrivalReminders: NSObject, CLLocationManagerDelegate, UNUserNotificationCenterDelegate {
    static let shared = ArrivalReminders()

    private let manager = CLLocationManager()
    private var pendingLocation: CheckedContinuation<CLLocationCoordinate2D?, Never>?
    private static let regionPrefix = "shop-"
    private static let radius: CLLocationDistance = 150

    override private init() {
        super.init()
        manager.delegate = self
        UNUserNotificationCenter.current().delegate = self
    }

    /// Asks for notifications and "Always" location, which iOS needs to notice an arrival
    /// while the app is closed.
    func requestPermissions() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse: manager.requestAlwaysAuthorization()
        default: break
        }
    }

    /// One reading of where you are now; nil if location isn't allowed or can't be found.
    func currentLocation() async -> CLLocationCoordinate2D? {
        if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted { return nil }
        pendingLocation?.resume(returning: nil)
        return await withCheckedContinuation { continuation in
            pendingLocation = continuation
            if manager.authorizationStatus == .notDetermined {
                manager.requestWhenInUseAuthorization()
            } else {
                manager.requestLocation()
            }
        }
    }

    /// Makes the monitored regions match the stores that have reminders on.
    func syncRegions(_ shops: [Shop]) {
        for region in manager.monitoredRegions where region.identifier.hasPrefix(Self.regionPrefix) {
            manager.stopMonitoring(for: region)
        }
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else { return }
        for shop in shops where shop.remindOnArrival == true {
            guard let lat = shop.latitude, let lon = shop.longitude else { continue }
            let region = CLCircularRegion(center: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                                          radius: Self.radius, identifier: Self.regionPrefix + shop.id.uuidString)
            region.notifyOnEntry = true
            region.notifyOnExit = false
            manager.startMonitoring(for: region)
        }
    }

    // MARK: Location callbacks

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let coordinate = locations.last?.coordinate
        Task { @MainActor in
            pendingLocation?.resume(returning: coordinate)
            pendingLocation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            pendingLocation?.resume(returning: nil)
            pendingLocation = nil
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            guard pendingLocation != nil else { return }
            switch manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways: manager.requestLocation()
            case .denied, .restricted:
                pendingLocation?.resume(returning: nil)
                pendingLocation = nil
            default: break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard region.identifier.hasPrefix("shop-"), let id = UUID(uuidString: String(region.identifier.dropFirst(5))) else { return }
        Task { @MainActor in notifyArrival(at: id) }
    }

    private func notifyArrival(at shopID: UUID) {
        let store = GroceryStore()
        guard let shop = store.shop(for: shopID), shop.remindOnArrival == true else { return }
        // At most once every two hours per store, so driving past isn't noisy.
        let key = "lastArrival-\(shopID.uuidString)"
        if let last = UserDefaults.standard.object(forKey: key) as? Date, Date().timeIntervalSince(last) < 7_200 { return }
        let items = store.widgetItems(shopID: shopID)
        guard !items.isEmpty else { return }
        UserDefaults.standard.set(Date(), forKey: key)

        let content = UNMutableNotificationContent()
        content.title = "You're at \(shop.name)"
        let names = items.prefix(5).map(\.name).joined(separator: ", ")
        content.body = "\(items.count) item\(items.count == 1 ? "" : "s") on your list: \(names)\(items.count > 5 ? "…" : "")"
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "arrival-\(shopID.uuidString)", content: content, trigger: nil))
    }

    // Show the banner even if the app happens to be open.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }
}
