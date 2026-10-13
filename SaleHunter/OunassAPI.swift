import Foundation

/// Talks to the same public API the Ounass Bahrain website uses.
/// Requests go out from the phone itself, one page (24 items) at a time.
enum OunassAPI {
    static let base = "https://bahrain.ounass.com"
    static let imageBase = "https://ounass-bh.atgcdn.ae/small_light(dw=900,of=webp)/pub/media/catalog/product"
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
        let products: [Product]   // every product on the page (before the app's price filter)
        let total: Int
        let hasMore: Bool
    }

    // MARK: - URLs

    private static let allowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return set
    }()

    private static func enc(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }

    static func listPath(_ f: SaleFilters) -> String {
        // Men's clothing or men's shoes only.
        let category = f.category == "shoes" ? "shoes" : "clothing"
        var path = "/api/v2/men/sale/" + category
        if SaleFilters.types(for: category).contains(where: { $0.value == f.subcategory }) {
            path += "/" + f.subcategory
        }
        return path
    }

    static func url(for f: SaleFilters, start: Int) -> URL? {
        var params: [(String, String)] = [("fh_start_index", String(start))]
        if let sort = f.sort.serverValue { params.append(("fh_sort_by", sort)) }
        if f.minDiscount > 0 {
            for step in SaleFilters.discountSteps where step >= f.minDiscount {
                params.append(("discountPercentBySaleId[]", String(step)))
            }
        }
        for b in f.brands { params.append(("designerCategoryName[]", b)) }
        if f.category == "shoes" {
            for s in f.shoeSizes { params.append(("shoeSizeCode[]", s)) }
        } else {
            for s in f.clothingSizes { params.append(("rtwSizeCode[]", s)) }
        }
        for c in f.colors { params.append(("colorFacet[]", c)) }
        let query = params.map { enc($0.0) + "=" + enc($0.1) }.joined(separator: "&")
        return URL(string: base + listPath(f) + "?" + query)
    }

    // MARK: - Networking

    private static func get(_ url: URL) async throws -> Data {
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
        return data
    }

    static func fetch(_ filters: SaleFilters, start: Int) async throws -> Page {
        guard let url = url(for: filters, start: start) else { throw APIError.badResponse(0) }
        let decoded = try JSONDecoder().decode(ListResponse.self, from: try await get(url))
        let raw = (decoded.plp?.styleColors ?? []).compactMap { $0.value }
        let products = raw.compactMap { $0.toProduct() }
        let total = decoded.plp?.pagination?.totalItems ?? products.count
        let hasNext = decoded.plp?.pagination?.nextPage?.href != nil
        return Page(products: products, total: total,
                    hasMore: hasNext && !raw.isEmpty && start + pageSize < total)
    }

    /// Brand names available for a category, straight from Ounass' filter list.
    static func fetchBrands(category: String, subcategory: String) async throws -> [String] {
        var f = SaleFilters()
        f.category = category
        f.subcategory = subcategory
        guard let url = url(for: f, start: 0) else { return [] }
        let decoded = try JSONDecoder().decode(FacetResponse.self, from: try await get(url))
        let facets = (decoded.plp?.facets ?? []).compactMap { $0.value }
        guard let designer = facets.first(where: { $0.name == "designerCategoryName" }) else { return [] }
        return (designer.options ?? []).compactMap { $0.value }.compactMap { option in
            if let href = option.href,
               let item = URLComponents(string: base + href)?.queryItems?
                .first(where: { $0.name == "designerCategoryName[]" }),
               let value = item.value, !value.isEmpty {
                return value
            }
            return option.name
        }
    }

    static func fetchDetail(_ productURL: URL) async throws -> ProductDetail {
        guard let url = URL(string: base + "/api/v2" + productURL.path) else { throw APIError.badResponse(0) }
        let decoded = try JSONDecoder().decode(DetailResponse.self, from: try await get(url))
        guard let pdp = decoded.pdp else { throw APIError.badResponse(200) }
        return pdp.toDetail()
    }

    // MARK: - URL helpers

    static func absolute(_ s: String?) -> URL? {
        guard let s, !s.isEmpty else { return nil }
        if s.hasPrefix("//") { return URL(string: "https:" + s) }
        if s.hasPrefix("http") { return URL(string: s) }
        if s.hasPrefix("/") { return URL(string: base + s) }
        return URL(string: s)
    }

    static func imageURL(_ s: String?) -> URL? {
        guard let s, !s.isEmpty else { return nil }
        if s.hasPrefix("//") || s.hasPrefix("http") { return absolute(s) }
        return URL(string: imageBase + (s.hasPrefix("/") ? s : "/" + s))
    }

    // MARK: - Lenient decoding

    struct Failable<T: Decodable>: Decodable {
        let value: T?
        init(from decoder: Decoder) { value = try? T(from: decoder) }
    }

    static func number<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ key: K) -> Double? {
        if let d = try? c.decode(Double.self, forKey: key) { return d }
        if let s = try? c.decode(String.self, forKey: key) { return Double(s) }
        return nil
    }

    static func string<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ keys: K...) -> String? {
        for key in keys {
            if let s = try? c.decode(String.self, forKey: key), !s.isEmpty { return s }
        }
        return nil
    }

    private struct ListResponse: Decodable { let plp: ListPLP? }

    private struct ListPLP: Decodable {
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
            totalItems = OunassAPI.number(c, .totalItems).map { Int($0) }
            nextPage = try? c.decode(Href.self, forKey: .nextPage)
        }
    }

    private struct RawSize: Decodable {
        let sizeCode: String?
        let stock: Double?
        let urgency: String?

        enum CodingKeys: String, CodingKey { case sizeCode, stock, stockUrgencyText }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            sizeCode = OunassAPI.string(c, .sizeCode)
            stock = OunassAPI.number(c, .stock)
            urgency = OunassAPI.string(c, .stockUrgencyText)
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

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = OunassAPI.string(c, .styleColorId)
            brand = OunassAPI.string(c, .designerCategoryEnglishName, .designerCategoryName)
            name = OunassAPI.string(c, .nameInEnglish, .name)
            thumbnail = OunassAPI.string(c, .thumbnail)
            url = OunassAPI.string(c, .url)
            price = OunassAPI.number(c, .price)
            slashedPrice = OunassAPI.number(c, .slashedPrice)
            discountPercent = OunassAPI.number(c, .discountPercent)
            outOfStock = try? c.decode(Bool.self, forKey: .outOfStock)
            category = OunassAPI.string(c, .productClassInEnglish)
            sizes = try? c.decode([Failable<RawSize>].self, forKey: .sizes)
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
                imageURL: OunassAPI.absolute(thumbnail),
                productURL: OunassAPI.absolute(url),
                sizes: inStock
            )
        }
    }

    // Facets (filter lists)
    private struct FacetResponse: Decodable { let plp: FacetPLP? }

    private struct FacetPLP: Decodable {
        let facets: [Failable<Facet>]?

        enum CodingKeys: String, CodingKey { case facets }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            facets = try? c.decode([Failable<Facet>].self, forKey: .facets)
        }
    }

    private struct Facet: Decodable {
        let name: String?
        let options: [Failable<FacetOption>]?

        enum CodingKeys: String, CodingKey { case name, options }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name = OunassAPI.string(c, .name)
            options = try? c.decode([Failable<FacetOption>].self, forKey: .options)
        }
    }

    private struct FacetOption: Decodable {
        let name: String?
        let href: String?

        enum CodingKeys: String, CodingKey { case name, href }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name = OunassAPI.string(c, .name)
            href = OunassAPI.string(c, .href)
        }
    }

    // Product page
    private struct DetailResponse: Decodable {
        let pdp: RawDetail?

        enum CodingKeys: String, CodingKey { case pdp }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            pdp = try? c.decode(RawDetail.self, forKey: .pdp)
        }
    }

    private struct RawMedia: Decodable {
        let src: String?
        enum CodingKeys: String, CodingKey { case src }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            src = OunassAPI.string(c, .src)
        }
    }

    private struct RawColor: Decodable {
        let label: String?
        let id: String?
        let hex: String?
        let inStock: Bool?
        let url: String?
        let thumbnail: String?

        enum CodingKeys: String, CodingKey { case label, styleColorId, hex, isInStock, url, thumbnail }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            label = OunassAPI.string(c, .label)
            id = OunassAPI.string(c, .styleColorId)
            hex = OunassAPI.string(c, .hex)
            inStock = try? c.decode(Bool.self, forKey: .isInStock)
            url = OunassAPI.string(c, .url)
            thumbnail = OunassAPI.string(c, .thumbnail)
        }
    }

    private struct RawDetail: Decodable {
        let brand: String?
        let name: String?
        let price: Double?
        let slashedPrice: Double?
        let discountPercent: Double?
        let media: [Failable<RawMedia>]?
        let thumbnail: String?
        let sizes: [Failable<RawSize>]?
        let description: String?
        let colors: [Failable<RawColor>]?

        enum CodingKeys: String, CodingKey {
            case designerCategoryEnglishName, designerCategoryName, designerName
            case nameInEnglish, name, price, slashedPrice, discountPercent
            case media, thumbnail, sizes, descriptionText, colors
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            brand = OunassAPI.string(c, .designerCategoryEnglishName, .designerCategoryName, .designerName)
            name = OunassAPI.string(c, .nameInEnglish, .name)
            price = OunassAPI.number(c, .price)
            slashedPrice = OunassAPI.number(c, .slashedPrice)
            discountPercent = OunassAPI.number(c, .discountPercent)
            media = try? c.decode([Failable<RawMedia>].self, forKey: .media)
            thumbnail = OunassAPI.string(c, .thumbnail)
            sizes = try? c.decode([Failable<RawSize>].self, forKey: .sizes)
            description = OunassAPI.string(c, .descriptionText)
            colors = try? c.decode([Failable<RawColor>].self, forKey: .colors)
        }

        func toDetail() -> ProductDetail {
            var images = (media ?? []).compactMap { $0.value?.src }
                .filter { src in
                    let path = src.lowercased().components(separatedBy: "?").first ?? ""
                    return [".jpg", ".jpeg", ".png", ".webp"].contains { path.hasSuffix($0) }
                }
                .compactMap { OunassAPI.imageURL($0) }
            if images.isEmpty, let t = OunassAPI.imageURL(thumbnail) { images = [t] }

            let sizeList = (sizes ?? []).compactMap { $0.value }.compactMap { s -> SizeStock? in
                guard let code = s.sizeCode else { return nil }
                return SizeStock(code: code, stock: Int(s.stock ?? 0), urgency: s.urgency)
            }
            let colorList = (colors ?? []).compactMap { $0.value }.compactMap { c -> ColorVariant? in
                guard let id = c.id else { return nil }
                return ColorVariant(id: id, label: c.label ?? "", hex: c.hex ?? "#888888",
                                    inStock: c.inStock ?? true, url: OunassAPI.absolute(c.url))
            }
            let p = price ?? 0
            return ProductDetail(
                brand: brand, name: name,
                price: p, was: slashedPrice ?? p,
                discount: Int((discountPercent ?? 0).rounded()),
                images: images, sizes: sizeList,
                description: ProductDetail.plainText(description ?? ""),
                colors: colorList
            )
        }
    }
}

struct SizeStock: Identifiable, Hashable {
    let code: String
    let stock: Int
    let urgency: String?
    var id: String { code }
}

struct ColorVariant: Identifiable, Hashable {
    let id: String
    let label: String
    let hex: String
    let inStock: Bool
    let url: URL?
}

struct ProductDetail {
    let brand: String?
    let name: String?
    let price: Double
    let was: Double
    let discount: Int
    let images: [URL]
    let sizes: [SizeStock]
    let description: String
    let colors: [ColorVariant]

    var totalStock: Int { sizes.reduce(0) { $0 + max(0, $1.stock) } }
    var inStockSizes: [String] { sizes.filter { $0.stock > 0 }.map(\.code) }

    static func plainText(_ html: String) -> String {
        var s = html.replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: .regularExpression)
        s = s.replacingOccurrences(of: "</(p|li|div)>", with: "\n", options: .regularExpression)
        s = s.replacingOccurrences(of: "<li[^>]*>", with: "• ", options: .regularExpression)
        s = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let entities = ["&amp;": "&", "&nbsp;": " ", "&quot;": "\"", "&#39;": "'", "&lt;": "<", "&gt;": ">"]
        for (k, v) in entities { s = s.replacingOccurrences(of: k, with: v) }
        s = s.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
