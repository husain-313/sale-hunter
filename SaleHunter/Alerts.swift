import Foundation
import BackgroundTasks
import UserNotifications

/// Settings for background deal alerts, stored on the phone.
enum AlertSettings {
    private static let defaults = UserDefaults.standard

    static var enabled: Bool {
        get { defaults.bool(forKey: "alertsEnabled") }
        set { defaults.set(newValue, forKey: "alertsEnabled") }
    }

    static var filters: SaleFilters {
        get {
            if let data = defaults.data(forKey: "alertFilters"),
               let saved = try? JSONDecoder().decode(SaleFilters.self, from: data) {
                return saved
            }
            return SaleFilters(minDiscount: 50)
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: "alertFilters")
            }
        }
    }

    static var lastCheck: Date? {
        get { defaults.object(forKey: "lastCheck") as? Date }
        set { defaults.set(newValue, forKey: "lastCheck") }
    }

    static var lastFound: Int {
        get { defaults.integer(forKey: "lastFound") }
        set { defaults.set(newValue, forKey: "lastFound") }
    }
}

enum AlertChecker {
    static let taskID = "com.husain313.salehunter.refresh"
    /// Pages checked per run (24 items each). Narrow alert filters = better coverage.
    static let pagesPerCheck = 4

    struct Result {
        let found: [Product]
        let checked: Int
        let baseline: Bool
    }

    static func scheduleNext() {
        guard AlertSettings.enabled else { return }
        let request = BGAppRefreshTaskRequest(identifier: taskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 3 * 3600)
        try? BGTaskScheduler.shared.submit(request)
    }

    static func runInBackground() async {
        scheduleNext()
        guard AlertSettings.enabled else { return }
        _ = try? await check(notify: true)
    }

    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Looks at the first few pages for the alert filters and reports items never seen before.
    static func check(notify: Bool) async throws -> Result {
        let filters = AlertSettings.filters
        let baseline = !Tracker.isKnown(filters)
        var found: [Product] = []
        var checked = 0
        var start = 0
        for index in 0..<pagesPerCheck {
            if index > 0 { try await Task.sleep(nanoseconds: 1_200_000_000) }
            let page = try await OunassAPI.fetch(filters, start: start)
            checked += page.products.count
            found += Tracker.record(page.products, baseline: baseline)
            if !page.hasMore { break }
            start += OunassAPI.pageSize
        }
        Tracker.markKnown(filters)
        AlertSettings.lastCheck = Date()
        AlertSettings.lastFound = found.count
        if notify && !found.isEmpty { await sendNotification(found) }
        return Result(found: found, checked: checked, baseline: baseline)
    }

    static func sendNotification(_ items: [Product]) async {
        let content = UNMutableNotificationContent()
        content.title = items.count == 1 ? "New deal on Ounass" : "\(items.count) new deals on Ounass"
        content.body = items
            .sorted { $0.discount > $1.discount }
            .prefix(3)
            .map { "\($0.brand) – \(Money.format($0.price)) (-\($0.discount)%)" }
            .joined(separator: "\n")
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }
}

/// Shows notifications as banners even while the app is open.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
