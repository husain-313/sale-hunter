import Foundation
import SwiftUI

/// Remembers what the user has already seen: first-seen time per item and last
/// price, so the app can mark items as NEW or PRICE DROP. Thread-safe so the
/// background check can use it too.
enum Tracker {
    private static let lock = NSLock()
    private static let defaults = UserDefaults.standard

    private static var firstSeen: [String: Double] = defaults.dictionary(forKey: "firstSeen") as? [String: Double] ?? [:]
    private static var lastPrice: [String: Double] = defaults.dictionary(forKey: "lastPrice") as? [String: Double] ?? [:]
    private static var dropFrom: [String: Double] = defaults.dictionary(forKey: "dropFrom") as? [String: Double] ?? [:]
    private static var dropAt: [String: Double] = defaults.dictionary(forKey: "dropAt") as? [String: Double] ?? [:]
    private static var knownFilters: Set<String> = Set(defaults.stringArray(forKey: "knownFilters") ?? [])

    private static func sync<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    private static var now: Double { Date().timeIntervalSince1970 }

    static func isKnown(_ filters: SaleFilters) -> Bool {
        sync { knownFilters.contains(filters.key) }
    }

    static func markKnown(_ filters: SaleFilters) {
        sync {
            knownFilters.insert(filters.key)
            defaults.set(Array(knownFilters), forKey: "knownFilters")
        }
    }

    /// Records items. Returns the ones never seen before (empty when `baseline`).
    @discardableResult
    static func record(_ products: [Product], baseline: Bool) -> [Product] {
        sync {
            let t = now
            var fresh: [Product] = []
            for p in products {
                if firstSeen[p.id] == nil {
                    firstSeen[p.id] = baseline ? 0 : t
                    if !baseline { fresh.append(p) }
                }
                if let old = lastPrice[p.id], p.price < old - 0.001 {
                    dropFrom[p.id] = old
                    dropAt[p.id] = t
                }
                lastPrice[p.id] = p.price
            }
            defaults.set(firstSeen, forKey: "firstSeen")
            defaults.set(lastPrice, forKey: "lastPrice")
            defaults.set(dropFrom, forKey: "dropFrom")
            defaults.set(dropAt, forKey: "dropAt")
            return fresh
        }
    }

    /// First seen in the last 24 hours.
    static func isNew(_ id: String) -> Bool {
        sync {
            guard let t = firstSeen[id], t > 0 else { return false }
            return now - t < 86_400
        }
    }

    /// Previous price if the item dropped in price in the last 3 days.
    static func previousPrice(_ id: String) -> Double? {
        sync {
            guard let at = dropAt[id], now - at < 3 * 86_400 else { return nil }
            return dropFrom[id]
        }
    }
}

/// Paged sale listing for the Sale tab.
@MainActor
final class SaleStore: ObservableObject {
    @Published var filters: SaleFilters {
        didSet {
            if let data = try? JSONEncoder().encode(filters) {
                UserDefaults.standard.set(data, forKey: "saleFilters")
            }
        }
    }
    @Published private(set) var products: [Product] = []
    @Published private(set) var total = 0
    @Published private(set) var isLoading = false
    @Published private(set) var canLoadMore = true
    @Published var errorMessage: String?

    private var nextStart = 0
    private var generation = 0
    private var baselineSession = false

    init() {
        if let data = UserDefaults.standard.data(forKey: "saleFilters"),
           let saved = try? JSONDecoder().decode(SaleFilters.self, from: data) {
            filters = saved
        } else {
            filters = SaleFilters()
        }
    }

    func refresh() async {
        generation += 1
        nextStart = 0
        total = 0
        products = []
        errorMessage = nil
        canLoadMore = true
        isLoading = false
        baselineSession = !Tracker.isKnown(filters)
        await loadMore()
    }

    func retry() async {
        errorMessage = nil
        canLoadMore = true
        await loadMore()
    }

    func loadMore() async {
        guard !isLoading, canLoadMore else { return }
        isLoading = true
        let gen = generation
        let current = filters
        do {
            let page = try await OunassAPI.fetch(current, start: nextStart)
            guard gen == generation else { return }
            Tracker.record(page.products, baseline: baselineSession)
            Tracker.markKnown(current)
            let existing = Set(products.map(\.id))
            products += page.products.filter { !existing.contains($0.id) }
            total = page.total
            nextStart += OunassAPI.pageSize
            canLoadMore = page.hasMore
        } catch {
            guard gen == generation else { return }
            errorMessage = error.localizedDescription
            canLoadMore = false
        }
        isLoading = false
    }
}

/// Saved items, kept on the phone.
@MainActor
final class FavoritesStore: ObservableObject {
    @Published private(set) var items: [Product] = []
    private let key = "favorites"

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode([Product].self, from: data) {
            items = saved
        }
    }

    func contains(_ product: Product) -> Bool {
        items.contains { $0.id == product.id }
    }

    func toggle(_ product: Product) {
        if let i = items.firstIndex(where: { $0.id == product.id }) {
            items.remove(at: i)
        } else {
            items.insert(product, at: 0)
        }
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
