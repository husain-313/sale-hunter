import Foundation
import SwiftUI

// MARK: - Stores

enum Store: String, Codable, CaseIterable, Identifiable {
    case ounass, farfetch, ssense, yoox, revolve, bfl

    var id: String { rawValue }

    var name: String {
        switch self {
        case .ounass: return "Ounass"
        case .farfetch: return "Farfetch"
        case .ssense: return "SSENSE"
        case .yoox: return "YOOX"
        case .revolve: return "REVOLVE"
        case .bfl: return "Brands For Less"
        }
    }

    /// Short line shown under the store picker.
    var blurb: String {
        switch self {
        case .ounass: return "Luxury · Bahrain store · BHD"
        case .farfetch: return "Global luxury · ships to Bahrain · prices converted from USD"
        case .ssense: return "Designer & streetwear · ships to Bahrain · prices converted from USD"
        case .yoox: return "Official luxury outlet · ships to Bahrain · prices converted from USD"
        case .revolve: return "Contemporary & luxury · ships to Bahrain · BHD"
        case .bfl: return "Brand outlet · Bahrain store · BHD"
        }
    }

    /// Ounass uses a direct API with server-side filters; the others are read from their pages.
    var usesAPI: Bool { self == .ounass }
}

// MARK: - Product

/// One sale item, as the app stores and shows it. Prices are always in BHD.
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
    let store: Store
    /// True when the price was converted from another currency.
    let converted: Bool

    init(id: String, brand: String, name: String, price: Double, was: Double, discount: Int,
         category: String, imageURL: URL?, productURL: URL?, sizes: [String],
         store: Store = .ounass, converted: Bool = false) {
        self.id = id
        self.brand = brand
        self.name = name
        self.price = price
        self.was = was
        self.discount = discount
        self.category = category
        self.imageURL = imageURL
        self.productURL = productURL
        self.sizes = sizes
        self.store = store
        self.converted = converted
    }

    enum CodingKeys: String, CodingKey {
        case id, brand, name, price, was, discount, category, imageURL, productURL, sizes, store, converted
    }

    // Lenient so favorites saved by older versions still load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        brand = (try? c.decode(String.self, forKey: .brand)) ?? ""
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        price = (try? c.decode(Double.self, forKey: .price)) ?? 0
        was = (try? c.decode(Double.self, forKey: .was)) ?? price
        discount = (try? c.decode(Int.self, forKey: .discount)) ?? 0
        category = (try? c.decode(String.self, forKey: .category)) ?? ""
        imageURL = try? c.decode(URL.self, forKey: .imageURL)
        productURL = try? c.decode(URL.self, forKey: .productURL)
        sizes = (try? c.decode([String].self, forKey: .sizes)) ?? []
        store = (try? c.decode(Store.self, forKey: .store)) ?? .ounass
        converted = (try? c.decode(Bool.self, forKey: .converted)) ?? false
    }

    func updated(price: Double, was: Double, discount: Int, sizes: [String]) -> Product {
        Product(id: id, brand: brand, name: name, price: price, was: was, discount: discount,
                category: category, imageURL: imageURL, productURL: productURL, sizes: sizes,
                store: store, converted: converted)
    }
}

enum Money {
    /// Bahraini dinar is pegged to the US dollar.
    static let usdToBHD = 0.376

    static func format(_ value: Double, approx: Bool = false) -> String {
        (approx ? "≈ " : "") + "BHD " + value.formatted(.number.precision(.fractionLength(0...3)))
    }

    static func toBHD(_ amount: Double, currency: String) -> Double {
        let c = currency.uppercased()
        if c == "BHD" || c == "BD" { return amount }
        // USD (and anything unexpected) — round converted prices to 0.1 BHD.
        return (amount * usdToBHD * 10).rounded() / 10
    }
}

// MARK: - Item types (shared by every store)

enum ItemType: String, CaseIterable, Identifiable, Codable {
    case tshirts, shirts, polos, knitwear, sweats, jackets, pants, jeans, shorts
    case sneakers, loafers, sandals, boots, formal

    var id: String { rawValue }

    var label: String {
        switch self {
        case .tshirts: return "T-Shirts"
        case .shirts: return "Shirts"
        case .polos: return "Polo Shirts"
        case .knitwear: return "Knitwear"
        case .sweats: return "Hoodies & Sweats"
        case .jackets: return "Jackets & Coats"
        case .pants: return "Pants"
        case .jeans: return "Jeans"
        case .shorts: return "Shorts"
        case .sneakers: return "Sneakers"
        case .loafers: return "Loafers"
        case .sandals: return "Sandals & Slides"
        case .boots: return "Boots"
        case .formal: return "Formal Shoes"
        }
    }

    var isShoe: Bool {
        switch self {
        case .sneakers, .loafers, .sandals, .boots, .formal: return true
        default: return false
        }
    }

    static func types(for category: String) -> [ItemType] {
        allCases.filter { $0.isShoe == (category == "shoes") }
    }

    /// Words used to recognise the type from a product name when a store has no type page.
    private var keywords: [String] {
        switch self {
        case .tshirts: return ["t-shirt", "tshirt", "t shirt", " tee", "tee ", "vest", "tank"]
        case .shirts: return ["shirt", "overshirt"]
        case .polos: return ["polo"]
        case .knitwear: return ["sweater", "knit", "cardigan", "jumper", "pullover", "turtleneck"]
        case .sweats: return ["sweatshirt", "hoodie", "hooded", "sweatpant", "jogger", "track"]
        case .jackets: return ["jacket", "coat", "blazer", "parka", "bomber", "gilet", "blouson", "anorak"]
        case .pants: return ["pant", "trouser", "chino", "cargo"]
        case .jeans: return ["jean", "denim"]
        case .shorts: return ["short"]
        case .sneakers: return ["sneaker", "trainer", "runner"]
        case .loafers: return ["loafer", "moccasin", "driver"]
        case .sandals: return ["sandal", "slide", "slipper", "flip flop", "mule", "espadrille"]
        case .boots: return ["boot"]
        case .formal: return ["derby", "oxford", "brogue", "lace-up", "monk", "formal"]
        }
    }

    private var excludes: [String] {
        switch self {
        case .shirts: return ["t-shirt", "tshirt", "t shirt", "sweatshirt", "polo", "overshirt jacket"]
        case .pants: return ["jean", "sweatpant", "jogger"]
        case .shorts: return ["short sleeve", "short-sleeve", "shorts sleeve"]
        default: return []
        }
    }

    func matches(_ product: Product) -> Bool {
        let text = " " + (product.name + " " + product.category).lowercased() + " "
        guard keywords.contains(where: { text.contains($0) }) else { return false }
        return !excludes.contains(where: { text.contains($0) })
    }

    // Store-specific type pages (nil = filter by name instead).

    var ounassSlug: String {
        switch self {
        case .tshirts: return "t-shirts"
        case .shirts: return "casual-shirts"
        case .polos: return "polo-shirts"
        case .knitwear: return "knitwear"
        case .sweats: return "sweats"
        case .jackets: return "coats-jackets"
        case .pants: return "pants"
        case .jeans: return "jeans"
        case .shorts: return "shorts"
        case .sneakers: return "sneakers"
        case .loafers: return "loafers"
        case .sandals: return "sandals"
        case .boots: return "boots"
        case .formal: return "formal-shoes"
        }
    }

    var farfetchSlug: String? {
        switch self {
        case .tshirts: return "t-shirts-vests-2"
        case .shirts: return "shirts-2"
        case .polos: return "polo-shirts-2"
        case .knitwear: return "sweaters-knitwear-2"
        case .jackets: return "jackets-2"
        case .pants: return "trousers-2"
        case .jeans: return "denim-2"
        default: return nil
        }
    }

    var revolvePath: String? {
        switch self {
        case .tshirts: return "tshirts/br/b9617f"
        case .shirts: return "shirts/br/c5304a"
        case .knitwear: return "sweaters-knits/br/48f1e6"
        case .jackets: return "jackets-coats/br/8591ec"
        case .pants: return "pants/br/f1d6c7"
        case .jeans: return "all-sale-items-denim/br/cf81ca"
        case .shorts: return "shorts/br/42f0e8"
        default: return nil
        }
    }
}

// MARK: - Sort

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
        case .discount: return "Biggest discount"
        }
    }

    /// Ounass sorts every item on the server; other stores sort the items loaded so far.
    static func options(for store: Store) -> [SortOption] {
        store.usesAPI ? allCases : [.featured, .discount, .priceLow, .priceHigh]
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

    func sort(_ list: [Product]) -> [Product] {
        switch self {
        case .discount: return list.sorted { $0.discount > $1.discount }
        case .priceLow: return list.sorted { $0.price < $1.price }
        case .priceHigh: return list.sorted { $0.price > $1.price }
        default: return list
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

// MARK: - Filters

/// Filters. For Ounass most are applied by the server; for other stores they're applied
/// on the phone to the pages loaded so far.
struct SaleFilters: Codable, Equatable {
    var store: Store = .ounass
    var minDiscount: Int = 0
    var category: String = "clothing"   // "clothing" or "shoes"
    var subcategory: String = ""        // ItemType raw value
    var brands: [String] = []
    var clothingSizes: [String] = []
    var shoeSizes: [String] = []
    var colors: [String] = []           // Ounass only
    var minPrice: Double?
    var maxPrice: Double?
    var sort: SortOption = .featured

    init() {}
    init(minDiscount: Int) { self.minDiscount = minDiscount }

    enum CodingKeys: String, CodingKey {
        case store, minDiscount, category, subcategory, brands, clothingSizes, shoeSizes, colors,
             minPrice, maxPrice, sort
    }

    // Lenient decoding so older saved settings never break the app.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        store = (try? c.decode(Store.self, forKey: .store)) ?? .ounass
        minDiscount = (try? c.decode(Int.self, forKey: .minDiscount)) ?? 0
        let savedCategory = (try? c.decode(String.self, forKey: .category)) ?? ""
        category = savedCategory == "shoes" ? "shoes" : "clothing"
        let savedType = (try? c.decode(String.self, forKey: .subcategory)) ?? ""
        subcategory = ItemType(rawValue: savedType).map { $0.isShoe == (category == "shoes") ? savedType : "" } ?? ""
        brands = (try? c.decode([String].self, forKey: .brands)) ?? []
        clothingSizes = (try? c.decode([String].self, forKey: .clothingSizes)) ?? []
        shoeSizes = (try? c.decode([String].self, forKey: .shoeSizes)) ?? []
        colors = (try? c.decode([String].self, forKey: .colors)) ?? []
        minPrice = try? c.decode(Double.self, forKey: .minPrice)
        maxPrice = try? c.decode(Double.self, forKey: .maxPrice)
        sort = (try? c.decode(SortOption.self, forKey: .sort)) ?? .featured
    }

    var itemType: ItemType? { ItemType(rawValue: subcategory) }

    /// Sizes that apply to the current category.
    var relevantSizes: [String] { category == "shoes" ? shoeSizes : clothingSizes }

    var activeCount: Int {
        [minDiscount > 0, !subcategory.isEmpty, !brands.isEmpty, !relevantSizes.isEmpty,
         store.usesAPI && !colors.isEmpty, minPrice != nil || maxPrice != nil]
            .filter { $0 }.count
    }

    var hasPriceRange: Bool { minPrice != nil || maxPrice != nil }

    func matchesPrice(_ p: Product) -> Bool {
        if let minPrice, p.price < minPrice { return false }
        if let maxPrice, p.price > maxPrice { return false }
        return true
    }

    /// Filters that the server didn't apply (everything except price for Ounass).
    func matchesLocally(_ p: Product, typeHandledByStore: Bool) -> Bool {
        guard matchesPrice(p) else { return false }
        if store.usesAPI { return true }
        if p.discount < minDiscount { return false }
        if !brands.isEmpty, !brands.contains(where: { $0.caseInsensitiveCompare(p.brand) == .orderedSame }) {
            return false
        }
        if let type = itemType, !typeHandledByStore, !type.matches(p) { return false }
        let sizes = relevantSizes
        if !sizes.isEmpty, !p.sizes.isEmpty {
            let wanted = Set(sizes.map(Self.normalizeSize))
            if !p.sizes.contains(where: { wanted.contains(Self.normalizeSize($0)) }) { return false }
        }
        return true
    }

    static func normalizeSize(_ size: String) -> String {
        let s = size.uppercased().trimmingCharacters(in: .whitespaces)
        switch s {
        case "2XL": return "XXL"
        case "3XL": return "XXXL"
        case "4XL": return "XXXXL"
        default: return s.replacingOccurrences(of: "EU ", with: "")
        }
    }

    /// Stable key (ignores sort) used to remember which filter combinations were already browsed.
    var key: String {
        [store.rawValue, String(minDiscount), category, subcategory,
         brands.map { $0.lowercased() }.sorted().joined(separator: ","),
         clothingSizes.sorted().joined(separator: ","),
         shoeSizes.sorted().joined(separator: ","),
         colors.sorted().joined(separator: ","),
         minPrice.map { String($0) } ?? "", maxPrice.map { String($0) } ?? ""]
            .joined(separator: "|")
    }

    // MARK: Static option lists

    static let discountSteps = [20, 30, 40, 50, 60, 70, 80]

    static let categories: [NamedOption] = [
        .init(value: "clothing", label: "Clothing"),
        .init(value: "shoes", label: "Shoes"),
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
