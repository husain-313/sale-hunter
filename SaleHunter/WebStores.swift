import Foundation
import UIKit
import WebKit

/// Reads sale pages of stores that have no public API (Farfetch, SSENSE, YOOX, REVOLVE,
/// Brands For Less). Each page is opened in a hidden web view on the phone — the same way
/// Safari would show it — and the product list is read from the page.
enum WebStores {
    struct Page {
        let products: [Product]
        let page: Int
        let pages: Int
        /// True when the store's own page already applied the item-type filter.
        let typeHandledByStore: Bool
        var hasMore: Bool { page < pages && !products.isEmpty }
    }

    enum WebError: LocalizedError {
        case noProducts(Store)

        var errorDescription: String? {
            switch self {
            case .noProducts(let store):
                return "Couldn't read \(store.name) right now — the page may be asking for a check. Try again in a few minutes."
            }
        }
    }

    // MARK: URLs

    /// `page` starts at 1.
    static func url(for f: SaleFilters, page: Int) -> (URL?, Bool) {
        let shoes = f.category == "shoes"
        let type = f.itemType
        switch f.store {
        case .ounass:
            return (nil, false)

        case .farfetch:
            var slug = shoes ? "shoes-2" : "clothing-2"
            var handled = false
            if let t = type, let s = t.farfetchSlug { slug = s; handled = true }
            let q = page > 1 ? "?page=\(page)" : ""
            return (URL(string: "https://www.farfetch.com/bh/shopping/men/sale/\(slug)/items.aspx\(q)"), handled)

        case .ssense:
            let q = page > 1 ? "?page=\(page)" : ""
            return (URL(string: "https://www.ssense.com/en-bh/men/sale/\(shoes ? "shoes" : "clothing")\(q)"), false)

        case .yoox:
            let q = page > 1 ? "?page=\(page)" : ""
            return (URL(string: "https://www.yoox.com/bh/men/\(shoes ? "shoes" : "clothing")/shoponline/sale\(q)"), false)

        case .revolve:
            var path = shoes ? "shoes/br/3d985a" : "all-sale-items/br/650eb6"
            var handled = false
            if let t = type, let p = t.revolvePath { path = p; handled = true }
            return (URL(string: "https://www.revolve.com/mens/sale/\(path)/?d=Mens&pageNum=\(page)"), handled)

        case .bfl:
            let q = page > 1 ? "?page=\(page)" : ""
            return (URL(string: "https://www.brandsforless.com/en-bh/men/\(shoes ? "shoes" : "clothing")/\(q)"), false)
        }
    }

    // MARK: Fetch

    @MainActor
    static func fetch(_ f: SaleFilters, page: Int) async throws -> Page {
        let (pageURL, handled) = url(for: f, page: page)
        guard let pageURL else { throw WebError.noProducts(f.store) }
        let json: String
        do {
            json = try await HiddenBrowser.shared.extract(from: pageURL, script: extractor(for: f.store),
                                                          prepare: f.store == .revolve ? revolveCookies : [],
                                                          pageWorld: f.store == .farfetch)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw WebError.noProducts(f.store)
        }
        guard let data = json.data(using: .utf8),
              let raw = try? JSONDecoder().decode(RawPage.self, from: data) else {
            throw WebError.noProducts(f.store)
        }
        var products = raw.items.compactMap { $0.toProduct(store: f.store, category: f.category) }

        // REVOLVE's "all sale" page also has shoes and accessories.
        if f.store == .revolve && !f.category.isEmpty && f.category != "shoes" && !handled {
            products = products.filter { p in
                !ItemType.types(for: "shoes").contains { $0.matches(p) } && !Self.looksLikeAccessory(p)
            }
        }
        return Page(products: products, page: max(page, raw.page ?? page), pages: max(raw.pages ?? page, 1),
                    typeHandledByStore: handled)
    }

    private static let accessoryWords = ["bag", "backpack", "wallet", "belt", "hat", "cap", "beanie", "scarf",
                                         "sock", "sunglass", "glasses", "watch", "bracelet", "necklace",
                                         "ring", "earring", "keychain", "card holder", "tote", "pouch"]

    static func looksLikeAccessory(_ p: Product) -> Bool {
        let text = " " + p.name.lowercased() + " "
        return accessoryWords.contains { text.contains(" " + $0) }
    }

    private static var revolveCookies: [HTTPCookie] {
        ["currency": "BHD", "currencyOverride": "BHD", "userLanguagePref": "en"].compactMap { name, value in
            HTTPCookie(properties: [.domain: ".revolve.com", .path: "/", .name: name, .value: value,
                                    .secure: "TRUE", .expires: Date().addingTimeInterval(86_400 * 365)])
        }
    }

    // MARK: Decoding

    private struct RawPage: Decodable {
        let items: [RawItem]
        let page: Int?
        let pages: Int?
    }

    private struct RawItem: Decodable {
        let id: String?
        let brand: String?
        let name: String?
        let price: Double?
        let was: Double?
        let disc: Double?
        let cur: String?
        let img: String?
        let url: String?
        let sizes: [String]?

        func toProduct(store: Store, category: String) -> Product? {
            guard let id, !id.isEmpty, let price, price > 0 else { return nil }
            let currency = cur ?? "USD"
            let now = Money.toBHD(price, currency: currency)
            var before = Money.toBHD(was ?? price, currency: currency)
            if before < now { before = now }
            var discount = Int((disc ?? 0).rounded())
            if discount <= 0, before > now { discount = Int(((1 - now / before) * 100).rounded()) }
            guard discount > 0 else { return nil }   // sale items only
            return Product(
                id: store.rawValue + ":" + id,
                brand: (brand ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                name: (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                price: now, was: before, discount: discount,
                category: category == "shoes" ? "Shoes" : "Clothing",
                imageURL: absolute(img, store: store),
                productURL: absolute(url, store: store),
                sizes: sizes ?? [],
                store: store,
                converted: !["BHD", "BD"].contains(currency.uppercased())
            )
        }

        private func absolute(_ s: String?, store: Store) -> URL? {
            guard let s, !s.isEmpty else { return nil }
            if s.hasPrefix("//") { return URL(string: "https:" + s) }
            if s.hasPrefix("http") { return URL(string: s) }
            let host: String
            switch store {
            case .farfetch: host = "https://www.farfetch.com"
            case .ssense: host = "https://www.ssense.com"
            case .yoox: host = "https://www.yoox.com"
            case .revolve: host = "https://www.revolve.com"
            case .bfl: host = "https://www.brandsforless.com"
            case .ounass: host = OunassAPI.base
            }
            return URL(string: host + (s.hasPrefix("/") ? s : "/" + s))
        }
    }

    // MARK: Page readers (JavaScript run inside the loaded page; return JSON text or null)

    static func extractor(for store: Store) -> String {
        let shared = """
        const num = t => { if (t == null) return null; const m = String(t).replace(/,/g, '').match(/\\d+(\\.\\d+)?/); return m ? parseFloat(m[0]) : null; };
        const cur = t => /BHD|BD/i.test(t || '') ? 'BHD' : 'USD';
        """
        switch store {
        case .ounass:
            return "return null;"

        case .farfetch:
            // Farfetch keeps the whole page's catalogue in a data blob (cards fill in lazily).
            return """
            const raw = window.__HYDRATION_STATE__; if (!raw) return null;
            const st = typeof raw === 'string' ? JSON.parse(raw) : raw;
            const cache = st.apolloInitialState || {};
            let conn = null;
            const find = (o, d) => { if (conn || !o || typeof o !== 'object' || d > 6) return;
              for (const k of Object.keys(o)) { if (k.indexOf('productCatalog:') === 0 && o[k] && o[k].edges) { conn = o[k]; return; } find(o[k], d + 1); } };
            find(st, 0); if (!conn) return null;
            const items = conn.edges.map(e => e.node).filter(Boolean).map(n => {
              const p = n.price || {}; const sale = p.__typename === 'ProductCatalogItemSalePrice';
              const brand = n.brand && n.brand.__ref && cache[n.brand.__ref] ? cache[n.brand.__ref].name : '';
              const img = ((n.images || [])[0] || {}).size480;
              const sizes = ((n.variationProperties || [])[0] || {}).values || [];
              return { id: n.id, brand, name: n.shortDescription || '',
                price: sale && p.value ? p.value.raw : null, was: sale && p.fullPriceValue ? p.fullPriceValue.raw : null,
                disc: sale && p.discountPercentage ? p.discountPercentage.raw : 0,
                cur: ((p.currency || {}).__ref || '').indexOf('BHD') >= 0 ? 'BHD' : 'USD',
                img: img ? img.url : '', url: '/bh' + ((n.resourceIdentifier || {}).path || ''),
                sizes: sizes.map(v => v.description).filter(Boolean) };
            });
            const current = +((location.search.match(/page=(\\d+)/) || [])[1] || 1);
            return JSON.stringify({ items, page: current, pages: Math.max(1, Math.ceil((conn.totalCount || 0) / 96)) });
            """

        case .ssense:
            return shared + """
            const links = [...document.querySelectorAll('a[href*="/product/"]')].filter(a => a.querySelector('script[type="application/ld+json"]'));
            if (!links.length) return null;
            const items = links.map(a => {
              let d = {}; try { d = JSON.parse(a.querySelector('script[type="application/ld+json"]').textContent); } catch (e) {}
              const c = a.cloneNode(true); c.querySelectorAll('script').forEach(x => x.remove());
              const prices = (c.textContent.match(/(BHD|\\$)\\s?[\\d,]+(\\.\\d+)?/g) || []).map(num);
              const offer = d.offers || {};
              const img = String(d.image || '').replace('__IMAGE_PARAMS__', 'b_white,c_lpad,g_south,ar_2:3/f_auto,c_limit,w_600,q_85');
              return { id: String(d.productID || d.sku || a.getAttribute('href')), brand: (d.brand || {}).name, name: d.name,
                price: offer.price != null ? +offer.price : prices[0], was: prices.length > 1 ? Math.max(...prices) : null,
                cur: offer.priceCurrency || cur(c.textContent), img, url: a.getAttribute('href'), sizes: [] };
            });
            const nums = [...document.querySelectorAll('a[href*="page="]')].map(a => +((a.getAttribute('href').match(/page=(\\d+)/) || [])[1] || 0));
            const current = +((location.search.match(/page=(\\d+)/) || [])[1] || 1);
            return JSON.stringify({ items, page: current, pages: Math.max(current, ...nums, 1) });
            """

        case .yoox:
            return """
            const el = document.getElementById('__NEXT_DATA__'); if (!el) return null;
            const d = JSON.parse(el.textContent);
            const ir = ((d.props || {}).pageProps || {}).algoliaServerState; if (!ir) return null;
            const r = Object.values(ir.initialResults)[0].results[0];
            const items = (r.hits || []).map(h => {
              const o = h.modelBestOfferByPrice || {}; const m = h.model || {};
              const brand = String((m.brand || [''])[0]).replace(/-\\d+$/, '');
              const imgPath = ((h.images || {}).url || '').replace('/~/', '/images/items/');
              return { id: h.objectID, brand, name: (m.categories || {}).micro || '',
                price: o.currentPrice, was: o.retailPrice, disc: o.markdownPercentageFromRetailPrice, cur: o.currency || 'USD',
                img: imgPath ? imgPath + '?impolicy=crop&width=600&height=764&gravity=Center' : '',
                url: '/bh/' + h.objectID + '/item', sizes: h.availableSizes || [] };
            });
            return JSON.stringify({ items, page: (r.page || 0) + 1, pages: r.nbPages || 1 });
            """

        case .revolve:
            return shared + """
            const tiles = [...document.querySelectorAll('li.js-plp-container')];
            if (!tiles.length) return null;
            const items = tiles.map(t => {
              const a = t.querySelector('a.js-plp-pdp-link2') || t.querySelector('a[href*="/dp/"]');
              const q = s => ((t.querySelector(s) || {}).textContent || '').trim();
              const sale = q('.price__sale') || q('.js-plp-price');
              const img = t.querySelector('img.js-plp-image') || t.querySelector('img');
              const href = a ? a.getAttribute('href').split('?')[0] : '';
              let name = q('.js-plp-name');
              // If the store answers in Arabic, build an English name from the product link.
              if (/[\u0600-\u06FF]/.test(name) || !name) {
                const slug = (href.split('/dp/')[0] || '').replace(/^\//, '');
                name = slug.split('-').filter(Boolean).map(w => w[0].toUpperCase() + w.slice(1)).join(' ');
              }
              return { id: t.id, brand: q('.js-plp-brand'), name,
                price: num(sale), was: num(q('.price__retail')), cur: cur(sale),
                img: img ? img.getAttribute('src') : '', url: href, sizes: [] };
            });
            const nums = [...document.querySelectorAll('a.js-pagination')].map(a => parseInt(a.textContent.trim(), 10)).filter(n => n > 0);
            const current = +((location.search.match(/pageNum=(\\d+)/) || [])[1] || 1);
            return JSON.stringify({ items, page: current, pages: Math.max(current, ...nums, 1) });
            """

        case .bfl:
            return """
            const s = [...document.querySelectorAll('script')].find(x => x.textContent.includes('__PRELOADED_STATE__'));
            if (!s) return null;
            const t = s.textContent; const start = t.indexOf('{', t.indexOf('__PRELOADED_STATE__'));
            const endMatch = /\\n\\s*window\\.__/.exec(t.slice(start)); const end = endMatch ? start + endMatch.index : t.length;
            const state = JSON.parse(t.slice(start, end).trim().replace(/;$/, ''));
            const dd = state.dynamicPage.data.data;
            const items = (dd.hits || []).map(h => {
              const p = h.price || {}; const rrp = p.rrp || {};
              return { id: String(h.id), brand: (h.brand || {}).label, name: (h.title || {}).label,
                price: p.current, was: rrp.price || p.old || null, disc: rrp.discountPercentage || p.discountPercentage || 0,
                cur: p.currency || 'BHD',
                img: h.captionImageURL ? 'https://f.bflcdn.com/t_pl/f_auto,q_auto/products/' + h.captionImageURL : '',
                url: '/en-bh/' + h.url,
                sizes: (h.sizes || []).filter(z => z.sizeStock > 0).map(z => z.sizeShortLabel || z.size) };
            });
            return JSON.stringify({ items, page: dd.page || 1, pages: dd.nbPages || 1 });
            """
        }
    }
}

/// A single off-screen web view that loads store pages and runs a reader script on them.
@MainActor
final class HiddenBrowser: NSObject, WKNavigationDelegate {
    static let shared = HiddenBrowser()

    private var webView: WKWebView?
    private var ruleList: WKContentRuleList?
    private var navContinuation: CheckedContinuation<Void, Never>?
    private var busy = false

    private static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"

    private func makeWebView() async -> WKWebView {
        if let webView { return webView }
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        if ruleList == nil {
            // Don't download pictures, video or fonts — only the product data is needed.
            let rules = #"[{"trigger":{"url-filter":".*","resource-type":["image","media","font"]},"action":{"type":"block"}}]"#
            ruleList = try? await WKContentRuleListStore.default()
                .compileContentRuleList(forIdentifier: "salehunter-lite", encodedContentRuleList: rules)
        }
        if let ruleList { config.userContentController.add(ruleList) }
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 1280, height: 900), configuration: config)
        view.customUserAgent = Self.userAgent
        view.navigationDelegate = self
        view.alpha = 0.01
        view.isUserInteractionEnabled = false
        // Keep it in the window so pages run normally; it's invisible and behind everything.
        if let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).flatMap(\.windows).first {
            window.insertSubview(view, at: 0)
        }
        webView = view
        return view
    }

    /// Loads `url`, then runs `script` (a function body returning JSON text or null)
    /// until it returns data or the timeout passes.
    func extract(from url: URL, script: String, prepare cookies: [HTTPCookie] = [],
                 pageWorld: Bool = false, timeout: TimeInterval = 30) async throws -> String {
        while busy { try await Task.sleep(nanoseconds: 200_000_000) }
        busy = true
        defer { busy = false }

        let view = await makeWebView()
        for cookie in cookies {
            await view.configuration.websiteDataStore.httpCookieStore.setCookie(cookie)
        }

        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            navContinuation = c
            view.load(URLRequest(url: url, timeoutInterval: timeout))
            // Never wait forever for navigation callbacks.
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                self.finishNavigation()
            }
        }

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            try Task.checkCancellation()
            if let text = await run(script, in: view, pageWorld: pageWorld), !text.isEmpty, text != "null" {
                view.stopLoading()
                return text
            }
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
        view.stopLoading()
        throw BrowserError.timedOut
    }

    enum BrowserError: Error { case timedOut }

    private func run(_ script: String, in view: WKWebView, pageWorld: Bool) async -> String? {
        await withCheckedContinuation { (c: CheckedContinuation<String?, Never>) in
            view.callAsyncJavaScript("try { \(script) } catch (e) { return null; }",
                                     arguments: [:], in: nil, in: pageWorld ? .page : .defaultClient) { result in
                switch result {
                case .success(let value): c.resume(returning: value as? String)
                case .failure: c.resume(returning: nil)
                }
            }
        }
    }

    private func finishNavigation() {
        navContinuation?.resume()
        navContinuation = nil
    }

    // Start reading as soon as the HTML is in; don't wait for every script and tracker.
    nonisolated func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            self.finishNavigation()
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in self.finishNavigation() }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in self.finishNavigation() }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                             withError error: Error) {
        Task { @MainActor in self.finishNavigation() }
    }
}
