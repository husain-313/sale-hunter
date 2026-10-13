import Foundation

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
}

enum Money {
    static func format(_ value: Double) -> String {
        "BHD " + value.formatted(.number.precision(.fractionLength(0...3)))
    }
}

/// Filters that map onto Ounass' own listing filters (sent to the server).
struct SaleFilters: Codable, Equatable {
    var minDiscount: Int = 0
    var category: String = ""      // "", clothing, shoes, accessories, bags, grooming
    var brand: String = ""
    var clothingSize: String = ""
    var shoeSize: String = ""

    var activeCount: Int {
        [minDiscount > 0, !category.isEmpty, !brand.isEmpty, !clothingSize.isEmpty, !shoeSize.isEmpty]
            .filter { $0 }.count
    }

    /// Stable key used to remember which filter combinations were already browsed.
    var key: String {
        "\(minDiscount)|\(category)|\(brand.lowercased())|\(clothingSize)|\(shoeSize)"
    }

    static let discountSteps = [20, 30, 40, 50, 60, 70, 80]

    static let categories: [(value: String, label: String)] = [
        ("", "All categories"),
        ("clothing", "Clothing"),
        ("shoes", "Shoes"),
        ("accessories", "Accessories"),
        ("bags", "Bags"),
        ("grooming", "Grooming"),
    ]

    static let clothingSizes = ["XS", "S", "M", "L", "XL", "XXL", "XXXL"]

    static let shoeSizes = ["39", "40", "40.5", "41", "41.5", "42", "42.5", "43",
                            "43.5", "44", "44.5", "45", "46", "47"]

    static let popularBrands = [
        "adidas", "Ami Paris", "BOSS", "Burberry", "Casablanca", "Dolce & Gabbana",
        "Emporio Armani", "Fear Of God", "Fear of God Essentials", "Gucci", "MSGM",
        "New Balance", "Nike", "Off-White", "Polo Ralph Lauren", "Prada", "Represent",
        "Sandro", "Tommy Hilfiger", "Valentino Garavani", "Versace", "Y-3", "Zegna",
    ]
}
