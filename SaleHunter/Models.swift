import Foundation
import SwiftUI

/// One sale item, as the app stores and shows it.
struct Product: Codable, Identifiable, Hashable {
    let id: String
    let brand: String
    let name: String
    let price: Double
    let was: Double
    let discount: Int
    let category: String
    let imageURL: URL?
    let productURL: URL?
    let sizes: [String]

    func updated(price: Double, was: Double, discount: Int, sizes: [String]) -> Product {
        Product(id: id, brand: brand, name: name, price: price, was: was, discount: discount,
                category: category, imageURL: imageURL, productURL: productURL, sizes: sizes)
    }
}

enum Money {
    static func format(_ value: Double) -> String {
        "BHD " + value.formatted(.number.precision(.fractionLength(0...3)))
    }
}

/// Sort orders. All but `discount` are done by Ounass across every item.
enum SortOption: String, Codable, CaseIterable, Identifiable {
    case featured, newest, wishlisted, priceLow, priceHigh, discount

    var id: String { rawValue }

    var label: String {
        switch self {
        case .featured: return "Featured"
        case .newest: return "Newest"
        case .wishlisted: return "Most wishlisted"
        case .priceLow: return "Price: low to high"
        case .priceHigh: return "Price: high to low"
        case .discount: return "Biggest discount (loaded items)"
        }
    }

    /// Value of Ounass' `fh_sort_by` parameter.
    var serverValue: String? {
        switch self {
        case .featured, .discount: return nil
        case .newest: return "-newness_bh"
        case .wishlisted: return "-wishlistcount_bh,newness_bh"
        case .priceLow: return "pricebysaleid-1_bh"
        case .priceHigh: return "-pricebysaleid-1_bh"
        }
    }
}

struct NamedOption: Identifiable, Hashable {
    let value: String
    let label: String
    var id: String { value }
}

struct ColorOption: Identifiable, Hashable {
    let id: String      // Ounass colour id
    let name: String
    let hex: String
}

/// Filters. Everything except the price range is applied by Ounass itself.
struct SaleFilters: Codable, Equatable {
    var minDiscount: Int = 0
    var category: String = ""
    var subcategory: String = ""
    var brands: [String] = []
    var clothingSizes: [String] = []
    var shoeSizes: [String] = []
    var colors: [String] = []
    var minPrice: Double?
    var maxPrice: Double?
    var sort: SortOption = .featured

    init() {}
    init(minDiscount: Int) { self.minDiscount = minDiscount }

    enum CodingKeys: String, CodingKey {
        case minDiscount, category, subcategory, brands, clothingSizes, shoeSizes, colors, minPrice, maxPrice, sort
    }

    // Lenient decoding so older saved settings never break the app.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        minDiscount = (try? c.decode(Int.self, forKey: .minDiscount)) ?? 0
        category = (try? c.decode(String.self, forKey: .category)) ?? ""
        subcategory = (try? c.decode(String.self, forKey: .subcategory)) ?? ""
        brands = (try? c.decode([String].self, forKey: .brands)) ?? []
        clothingSizes = (try? c.decode([String].self, forKey: .clothingSizes)) ?? []
        shoeSizes = (try? c.decode([String].self, forKey: .shoeSizes)) ?? []
        colors = (try? c.decode([String].self, forKey: .colors)) ?? []
        minPrice = try? c.decode(Double.self, forKey: .minPrice)
        maxPrice = try? c.decode(Double.self, forKey: .maxPrice)
        sort = (try? c.decode(SortOption.self, forKey: .sort)) ?? .featured
    }

    var activeCount: Int {
        [minDiscount > 0, !subcategory.isEmpty, !brands.isEmpty, !clothingSizes.isEmpty,
         !colors.isEmpty, minPrice != nil || maxPrice != nil]
            .filter { $0 }.count
    }

    var hasPriceRange: Bool { minPrice != nil || maxPrice != nil }

    func matchesPrice(_ p: Product) -> Bool {
        if let minPrice, p.price < minPrice { return false }
        if let maxPrice, p.price > maxPrice { return false }
        return true
    }

    /// Stable key (ignores sort) used to remember which filter combinations were already browsed.
    var key: String {
        [String(minDiscount), category, subcategory,
         brands.map { $0.lowercased() }.sorted().joined(separator: ","),
         clothingSizes.sorted().joined(separator: ","),
         shoeSizes.sorted().joined(separator: ","),
         colors.sorted().joined(separator: ","),
         minPrice.map { String($0) } ?? "", maxPrice.map { String($0) } ?? ""]
            .joined(separator: "|")
    }

    // MARK: Static option lists (taken from Ounass Bahrain's own filters)

    static let discountSteps = [20, 30, 40, 50, 60, 70, 80]

    static let clothingTypes: [NamedOption] = [
        .init(value: "t-shirts", label: "T-Shirts"),
        .init(value: "casual-shirts", label: "Casual Shirts"),
        .init(value: "polo-shirts", label: "Polo Shirts"),
        .init(value: "sweats", label: "Sweats"),
        .init(value: "knitwear", label: "Knitwear"),
        .init(value: "coats-jackets", label: "Coats & Jackets"),
        .init(value: "blazer", label: "Blazers"),
        .init(value: "pants", label: "Pants"),
        .init(value: "jeans", label: "Jeans"),
        .init(value: "shorts", label: "Shorts"),
        .init(value: "swimwear", label: "Swimwear"),
        .init(value: "underwear", label: "Underwear"),
    ]

    static let colorOptions: [ColorOption] = [
        .init(id: "13", name: "Black", hex: "#000000"),
        .init(id: "26", name: "White", hex: "#FFFFFF"),
        .init(id: "14", name: "Blue", hex: "#5E96E1"),
        .init(id: "19", name: "Grey", hex: "#9A9A9A"),
        .init(id: "15", name: "Brown", hex: "#8B5A2B"),
        .init(id: "21", name: "Neutral", hex: "#D8C8AE"),
        .init(id: "20", name: "Green", hex: "#4E9A5B"),
        .init(id: "25", name: "Red", hex: "#D93A3A"),
        .init(id: "16", name: "Burgundy", hex: "#7A1F2B"),
        .init(id: "23", name: "Pink", hex: "#F2A0B8"),
        .init(id: "24", name: "Purple", hex: "#8E5CC2"),
        .init(id: "22", name: "Orange", hex: "#F08C2E"),
        .init(id: "27", name: "Yellow", hex: "#F4D03F"),
        .init(id: "248", name: "Gold", hex: "#C9A43B"),
        .init(id: "18", name: "Multicolour", hex: "multi"),
    ]

    static let clothingSizeOptions = ["XS", "S", "M", "L", "XL", "XXL", "XXXL"]

    static let shoeSizeOptions = ["39", "40", "40.5", "41", "41.5", "42", "42.5", "43",
                                  "43.5", "44", "44.5", "45", "46", "47"]

    static let popularBrands = [
        "adidas", "Ami Paris", "BOSS", "Burberry", "Casablanca", "Dolce & Gabbana",
        "Emporio Armani", "Fear Of God", "Fear of God Essentials", "Gucci", "MSGM",
        "New Balance", "Nike", "Off-White", "Polo Ralph Lauren", "Prada", "Represent",
        "Sandro", "Tommy Hilfiger", "Valentino Garavani", "Versace", "Y-3", "Zegna",
    ]
}

extension Color {
    init(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        let v = UInt64(s, radix: 16) ?? 0
        self.init(red: Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >> 8) & 0xFF) / 255,
                  blue: Double(v & 0xFF) / 255)
    }
}

enum NumberInput {
    /// Accepts Arabic digits and Arabic/European decimal separators.
    static func parse(_ text: String) -> Double? {
        let map: [Character: Character] = ["٠": "0", "١": "1", "٢": "2", "٣": "3", "٤": "4",
                                           "٥": "5", "٦": "6", "٧": "7", "٨": "8", "٩": "9",
                                           "٫": ".", ",": "."]
        let cleaned = String(text.map { map[$0] ?? $0 }).trimmingCharacters(in: .whitespaces)
        guard let value = Double(cleaned), value >= 0 else { return nil }
        return value
    }
}
