import Foundation
import BackgroundTasks
import UserNotifications

/// Settings for background alerts, stored on the phone.
enum AlertSettings {
    private static let defaults = UserDefaults.standard

    static var enabled: Bool {
        get { defaults.bool(forKey: "alertsEnabled") }
        set { defaults.set(newValue, forKey: "alertsEnabled") }
    }

    static var favoritesAlerts: Bool {
        get { defaults.object(forKey: "favoritesAlerts") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "favoritesAlerts") }
    }

    static var filters: SaleFilters {
        get {
            if let data = defaults.data(forKey: "alertFilters.v2"),
               let saved = try? JSONDecoder().decode(SaleFilters.self, from: data) {
                return saved
            }
            return SaleFilters(minDiscount: 50)
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: "alertFilters.v2")
            }
        }
    }

    static var lastCheck: Date? {
        get { defaults.object(forKey: "lastCheck") as? Date }
        set { defaults.set(newValue, forKey: "lastCheck") }
    }

    /// Stock warnings already sent ("<id>|low" / "<id>|out"), so each is sent once.
    static var stockNotified: Set<String> {
        get { Set(defaults.stringArray(forKey: "stockNotified") ?? []) }
        set { defaults.set(Array(newValue), forKey: "stockNotified") }
    }
}

struct FavoriteChange {
    enum Kind { case priceDrop(old: Double), lowStock, soldOut }
    let product: Product
    let kind: Kind

    var line: String {
        switch kind {
        case .priceDrop(let old):
            return "\(product.brand): \(Money.format(old)) → \(Money.format(product.price))"
        case .lowStock:
            return "\(product.brand) \(product.name): almost sold out"
        case .soldOut:
            return "\(product.brand) \(product.name): sold out"
        }
    }
}

enum AlertChecker {
    static let taskID = "com.husain313.salehunter.refresh"
    /// Pages of newest items checked per run (24 items each).
    static let pagesPerCheck = 3
    /// Favorites checked per run.
    static let favoritesPerCheck = 10

    struct Result {
        let found: [Product]
        let checked: Int
        let baseline: Bool
        let favoriteChanges: [FavoriteChange]
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

    /// New items (sorted by Ounass' newest first) matching the alert filters,
    /// plus price/stock changes on favorites.
    static func check(notify: Bool) async throws -> Result {
        var filters = AlertSettings.filters
        filters.sort = .newest
        let baseline = !Tracker.isKnown(filters)
        var found: [Product] = []
        var checked = 0
        var start = 0
        for index in 0..<pagesPerCheck {
            if index > 0 { try await Task.sleep(nanoseconds: 700_000_000) }
            let page = try await OunassAPI.fetch(filters, start: start)
            checked += page.products.count
            found += Tracker.record(page.products, baseline: baseline).filter { filters.matchesPrice($0) }
            if !page.hasMore { break }
            start += OunassAPI.pageSize
        }
        Tracker.markKnown(filters)

        let changes = AlertSettings.favoritesAlerts ? await checkFavorites() : []
        AlertSettings.lastCheck = Date()

        if notify {
            if !found.isEmpty { await sendDealsNotification(found) }
            if !changes.isEmpty { await sendFavoritesNotification(changes) }
        }
        return Result(found: found, checked: checked, baseline: baseline, favoriteChanges: changes)
    }

    static func checkFavorites() async -> [FavoriteChange] {
        var favorites = FavoritesStore.loadSaved()
        guard !favorites.isEmpty else { return [] }
        var notified = AlertSettings.stockNotified
        var changes: [FavoriteChange] = []

        for index in favorites.indices.prefix(favoritesPerCheck) {
            let fav = favorites[index]
            guard let url = fav.productURL,
                  let detail = try? await OunassAPI.fetchDetail(url),
                  detail.price > 0 else { continue }
            try? await Task.sleep(nanoseconds: 500_000_000)

            let updated = fav.updated(price: detail.price, was: detail.was,
                                      discount: detail.discount, sizes: detail.inStockSizes)
            if detail.price < fav.price - 0.001 {
                changes.append(FavoriteChange(product: updated, kind: .priceDrop(old: fav.price)))
            }
            if !detail.sizes.isEmpty {
                let stock = detail.totalStock
                if stock == 0 {
                    if !notified.contains(fav.id + "|out") {
                        changes.append(FavoriteChange(product: updated, kind: .soldOut))
                        notified.insert(fav.id + "|out")
                    }
                } else if stock <= 2 {
                    if !notified.contains(fav.id + "|low") {
                        changes.append(FavoriteChange(product: updated, kind: .lowStock))
                        notified.insert(fav.id + "|low")
                    }
                } else {
                    notified.remove(fav.id + "|low")
                    notified.remove(fav.id + "|out")
                }
            }
            Tracker.record([updated], baseline: true)
            favorites[index] = updated
        }

        // Merge into the latest saved list (the user may have changed it meanwhile).
        var latest = FavoritesStore.loadSaved()
        for item in favorites {
            if let i = latest.firstIndex(where: { $0.id == item.id }) { latest[i] = item }
        }
        FavoritesStore.save(latest)
        AlertSettings.stockNotified = notified
        return changes
    }

    static func sendDealsNotification(_ items: [Product]) async {
        let content = UNMutableNotificationContent()
        content.title = items.count == 1 ? "New deal on Ounass" : "\(items.count) new deals on Ounass"
        content.body = items
            .sorted { $0.discount > $1.discount }
            .prefix(3)
            .map { "\($0.brand) – \(Money.format($0.price)) (-\($0.discount)%)" }
            .joined(separator: "\n")
        content.sound = .default
        await deliver(content)
    }

    static func sendFavoritesNotification(_ changes: [FavoriteChange]) async {
        let drops = changes.filter { if case .priceDrop = $0.kind { return true } else { return false } }
        let content = UNMutableNotificationContent()
        content.title = drops.isEmpty ? "Update on your favorites" : "Price drop on your favorites"
        content.body = changes.prefix(4).map(\.line).joined(separator: "\n")
        content.sound = .default
        await deliver(content)
    }

    private static func deliver(_ content: UNNotificationContent) async {
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
