import Foundation

/// Talks to the same public listing API the Ounass Bahrain website uses.
/// Requests go out from the phone itself, one page (24 items) at a time.
enum OunassAPI {
    static let base = "https://bahrain.ounass.com"
    static let pageSize = 24

    enum APIError: LocalizedError {
        case blocked
        case badResponse(Int)

        var errorDescription: String? {
            switch self {
            case .blocked:
                return "Ounass is asking for a browser check right now. Wait a few minutes, then pull down to refresh."
            case .badResponse(let code):
                return "Ounass returned an error (\(code)). Try again later."
            }
        }
    }

    struct Page {
        let products: [Product]
        let total: Int
        let hasMore: Bool
    }

    private static let allowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return set
    }()

    private static func enc(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }

    static func url(for filters: SaleFilters, start: Int) -> URL? {
        var path = "/api/v2/men/sale"
        if !filters.category.isEmpty { path += "/" + filters.category }

        var params: [(String, String)] = [("fh_start_index", String(start))]
        if filters.minDiscount > 0 {
            for step in SaleFilters.discountSteps where step >= filters.minDiscount {
                params.append(("discountPercentBySaleId[]", String(step)))
            }
        }
        let brand = filters.brand.trimmingCharacters(in: .whitespaces)
        if !brand.isEmpty { params.append(("designerCategoryName[]", brand)) }
        if !filters.clothingSize.isEmpty { params.append(("rtwSizeCode[]", filters.clothingSize)) }
        if !filters.shoeSize.isEmpty { params.append(("shoeSizeCode[]", filters.shoeSize)) }

        let query = params.map { enc($0.0) + "=" + enc($0.1) }.joined(separator: "&")
        return URL(string: base + path + "?" + query)
    }

    static func fetch(_ filters: SaleFilters, start: Int) async throws -> Page {
        guard let url = url(for: filters, start: start) else { throw APIError.badResponse(0) }
        var request = URLRequest(url: url)
        request.timeoutInterval = 25
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")

        let (data, response) = try await URLSession.shared.data(for: request)
        let http = response as? HTTPURLResponse
        let code = http?.statusCode ?? 0
        let type = http?.value(forHTTPHeaderField: "Content-Type") ?? ""
        if code == 403 || code == 429 || type.contains("text/html") { throw APIError.blocked }
        guard code == 200 else { throw APIError.badResponse(code) }

        let decoded = try JSONDecoder().decode(Response.self, from: data)
        let raw = (decoded.plp?.styleColors ?? []).compactMap { $0.value }
        let products = raw.compactMap { $0.toProduct() }
        let total = decoded.plp?.pagination?.totalItems ?? products.count
        let hasNext = decoded.plp?.pagination?.nextPage?.href != nil
        let hasMore = hasNext && !raw.isEmpty && start + pageSize < total
        return Page(products: products, total: total, hasMore: hasMore)
    }

    // MARK: - Lenient decoding (the API mixes banners and products, numbers may be strings)

    private struct Failable<T: Decodable>: Decodable {
        let value: T?
        init(from decoder: Decoder) { value = try? T(from: decoder) }
    }

    private struct Response: Decodable {
        let plp: PLP?
    }

    private struct PLP: Decodable {
        let pagination: Pagination?
        let styleColors: [Failable<RawProduct>]?

        enum CodingKeys: String, CodingKey { case pagination, styleColors }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            pagination = try? c.decode(Pagination.self, forKey: .pagination)
            styleColors = try? c.decode([Failable<RawProduct>].self, forKey: .styleColors)
        }
    }

    private struct Href: Decodable { let href: String? }

    private struct Pagination: Decodable {
        let totalItems: Int?
        let nextPage: Href?

        enum CodingKeys: String, CodingKey { case totalItems, nextPage }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            if let n = try? c.decode(Int.self, forKey: .totalItems) {
                totalItems = n
            } else if let s = try? c.decode(String.self, forKey: .totalItems) {
                totalItems = Int(s)
            } else {
                totalItems = nil
            }
            nextPage = try? c.decode(Href.self, forKey: .nextPage)
        }
    }

    private struct RawSize: Decodable {
        let sizeCode: String?
        let stock: Double?

        enum CodingKeys: String, CodingKey { case sizeCode, stock }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            sizeCode = try? c.decode(String.self, forKey: .sizeCode)
            stock = RawProduct.number(c, .stock)
        }
    }

    private struct RawProduct: Decodable {
        let id: String?
        let brand: String?
        let name: String?
        let thumbnail: String?
        let url: String?
        let price: Double?
        let slashedPrice: Double?
        let discountPercent: Double?
        let outOfStock: Bool?
        let category: String?
        let sizes: [Failable<RawSize>]?

        enum CodingKeys: String, CodingKey {
            case styleColorId, designerCategoryEnglishName, designerCategoryName
            case nameInEnglish, name, thumbnail, url, price, slashedPrice
            case discountPercent, outOfStock, productClassInEnglish, sizes
        }

        static func number<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ key: K) -> Double? {
            if let d = try? c.decode(Double.self, forKey: key) { return d }
            if let s = try? c.decode(String.self, forKey: key) { return Double(s) }
            return nil
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try? c.decode(String.self, forKey: .styleColorId)
            brand = (try? c.decode(String.self, forKey: .designerCategoryEnglishName))
                ?? (try? c.decode(String.self, forKey: .designerCategoryName))
            name = (try? c.decode(String.self, forKey: .nameInEnglish))
                ?? (try? c.decode(String.self, forKey: .name))
            thumbnail = try? c.decode(String.self, forKey: .thumbnail)
            url = try? c.decode(String.self, forKey: .url)
            price = Self.number(c, .price)
            slashedPrice = Self.number(c, .slashedPrice)
            discountPercent = Self.number(c, .discountPercent)
            outOfStock = try? c.decode(Bool.self, forKey: .outOfStock)
            category = try? c.decode(String.self, forKey: .productClassInEnglish)
            sizes = try? c.decode([Failable<RawSize>].self, forKey: .sizes)
        }

        private static func absolute(_ s: String?) -> URL? {
            guard let s, !s.isEmpty else { return nil }
            if s.hasPrefix("//") { return URL(string: "https:" + s) }
            if s.hasPrefix("/") { return URL(string: OunassAPI.base + s) }
            return URL(string: s)
        }

        func toProduct() -> Product? {
            guard let id, let price, outOfStock != true else { return nil }
            let inStock = (sizes ?? []).compactMap { $0.value }
                .filter { ($0.stock ?? 0) > 0 }
                .compactMap { $0.sizeCode }
            return Product(
                id: id,
                brand: (brand ?? "").trimmingCharacters(in: .whitespaces),
                name: (name ?? "").trimmingCharacters(in: .whitespaces),
                price: price,
                was: slashedPrice ?? price,
                discount: Int((discountPercent ?? 0).rounded()),
                category: category ?? "",
                imageURL: Self.absolute(thumbnail),
                productURL: Self.absolute(url),
                sizes: inStock
            )
        }
    }
}
