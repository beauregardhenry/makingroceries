import UserNotifications

/// A quiet morning reminder, the day before something at home is due to be used.
enum ExpiryReminders {
    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "expiryReminders") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "expiryReminders") }
    }

    private static let prefix = "expiry-"

    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    /// Replaces the scheduled reminders to match what's at home now. At most 20 days are scheduled.
    static func reschedule(_ stock: [StockEntry], now: Date = Date()) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(prefix) })
        guard enabled else { return }

        let cal = Calendar.current
        var byDay: [Date: [String]] = [:]
        for entry in stock {
            let expiryDay = cal.startOfDay(for: entry.expires)
            // Remind the morning before, or this morning if it's due today and 9am hasn't passed.
            var remindDay = cal.date(byAdding: .day, value: -1, to: expiryDay) ?? expiryDay
            if remindDay < cal.startOfDay(for: now) { remindDay = cal.startOfDay(for: now) }
            byDay[remindDay, default: []].append(entry.name)
        }

        for (day, names) in byDay.sorted(by: { $0.key < $1.key }).prefix(20) {
            guard let fire = cal.date(bySettingHour: 9, minute: 0, second: 0, of: day), fire > now else { continue }
            let content = UNMutableNotificationContent()
            content.title = "Use soon"
            content.body = names.sorted().joined(separator: ", ") + (names.count == 1 ? " is" : " are") + " due to be used by tomorrow."
            content.sound = .default
            let parts = cal.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: prefix + "\(Int(day.timeIntervalSince1970))", content: content, trigger: trigger))
        }
    }
}
