import SwiftUI

private let gridColumns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

// MARK: - Sale tab

struct SaleView: View {
    @StateObject private var store = SaleStore()
    @State private var search = ""
    @State private var showFilters = false
    @State private var path: [Product] = []

    private var shown: [Product] {
        var list = store.products
        let words = search.lowercased().split(separator: " ").map(String.init)
        if !words.isEmpty {
            list = list.filter { p in
                let hay = (p.brand + " " + p.name).lowercased()
                return words.allSatisfy { hay.contains($0) }
            }
        }
        if !store.filters.store.usesAPI || store.filters.sort == .discount {
            list = store.filters.sort.sort(list)
        }
        return list
    }

    private var categoryBinding: Binding<String> {
        Binding(
            get: { store.filters.category },
            set: { newValue in
                guard newValue != store.filters.category else { return }
                store.filters.category = newValue
                store.filters.subcategory = ""
                Task { await store.refresh() }
            }
        )
    }

    private var storeBinding: Binding<Store> {
        Binding(
            get: { store.filters.store },
            set: { newValue in
                guard newValue != store.filters.store else { return }
                store.filters.store = newValue
                if !SortOption.options(for: newValue).contains(store.filters.sort) {
                    store.filters.sort = .featured
                }
                Task { await store.refresh() }
            }
        )
    }

    private var sortBinding: Binding<SortOption> {
        Binding(
            get: { store.filters.sort },
            set: { newValue in
                guard newValue != store.filters.sort else { return }
                store.filters.sort = newValue
                // Other stores sort the loaded items on the phone — no reload needed.
                if store.filters.store.usesAPI { Task { await store.refresh() } }
            }
        )
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVStack(spacing: 12) {
                    StorePicker(selection: storeBinding)
                    Picker("Category", selection: categoryBinding) {
                        ForEach(SaleFilters.categories) { Text($0.label).tag($0.value) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    summary
                    LazyVGrid(columns: gridColumns, spacing: 12) {
                        ForEach(shown) { product in
                            ProductCard(product: product) { path.append(product) }
                        }
                    }
                    .padding(.horizontal, 16)
                    footer
                }
            }
            .navigationTitle("Sale Hunter")
            .searchable(text: $search, prompt: "Search brand or item")
            .refreshable { await store.refresh() }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Menu {
                        Picker("Sort", selection: sortBinding) {
                            ForEach(SortOption.options(for: store.filters.store)) { Text($0.label).tag($0) }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down.circle")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showFilters = true } label: {
                        Image(systemName: store.filters.activeCount > 0
                              ? "line.3.horizontal.decrease.circle.fill"
                              : "line.3.horizontal.decrease.circle")
                    }
                }
            }
            .navigationDestination(for: Product.self) { ProductDetailView(product: $0) }
            .sheet(isPresented: $showFilters) {
                FilterSheet(title: "Filters", filters: store.filters, localBrands: store.loadedBrands) { newFilters in
                    var updated = newFilters
                    updated.sort = store.filters.sort
                    store.filters = updated
                    Task { await store.refresh() }
                }
            }
            .task {
                if store.products.isEmpty { await store.refresh() }
            }
        }
    }

    @ViewBuilder private var summary: some View {
        if store.total > 0 {
            HStack(spacing: 6) {
                if store.filters.store.usesAPI {
                    Text("\(store.total.formatted()) \(store.filters.category == "shoes" ? "shoes" : "clothing items")")
                } else {
                    Text("\(store.products.count) items · page \(store.pagesLoaded) of \(store.totalPages.formatted())")
                }
                if store.filters.sort != .featured {
                    Text("· \(store.filters.sort.label)")
                }
                Spacer()
                if store.filters.activeCount > 0 {
                    Button("\(store.filters.activeCount) filter\(store.filters.activeCount == 1 ? "" : "s")") {
                        showFilters = true
                    }
                    .foregroundStyle(Theme.gold)
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 16)
            .padding(.top, 4)
        }
    }

    @ViewBuilder private var footer: some View {
        if let message = store.errorMessage {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle").font(.title2)
                Text(message).multilineTextAlignment(.center).font(.subheadline)
                Button("Try again") { Task { await store.retry() } }
                    .buttonStyle(.bordered)
            }
            .foregroundStyle(.secondary)
            .padding(32)
        } else if store.canLoadMore {
            if search.isEmpty && !store.autoLoadPaused {
                ProgressView()
                    .padding(32)
                    .id(store.pagesLoaded)
                    .onAppear { Task { await store.loadMore() } }
            } else {
                VStack(spacing: 8) {
                    if store.autoLoadPaused {
                        Text("Nothing in your price range on the last few pages.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Button(store.isLoading ? "Loading…" : "Load more items") {
                        Task { await store.resumeLoading() }
                    }
                    .buttonStyle(.bordered)
                    .disabled(store.isLoading)
                }
                .padding(24)
            }
        } else if store.products.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "tag.slash").font(.title2)
                Text("No items match these filters.")
                Button("Change filters") { showFilters = true }
                    .buttonStyle(.bordered)
                    .padding(.top, 4)
            }
            .foregroundStyle(.secondary)
            .padding(40)
        } else {
            Text("You've reached the end")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(32)
        }
    }
}

// MARK: - Product card

struct ProductCard: View {
    let product: Product
    let onOpen: () -> Void
    @EnvironmentObject private var favorites: FavoritesStore
    @Environment(\.openURL) private var openURL

    var body: some View {
        let isFavorite = favorites.contains(product)
        let previous = Tracker.previousPrice(product.id)

        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .top) {
                Color.white
                RemoteImage(url: product.imageURL)

                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Badge(text: "-\(product.discount)%", color: Theme.sale, textColor: .white)
                        if Tracker.isNew(product.id) { Badge(text: "NEW", color: Theme.fresh, textColor: .black) }
                        if previous != nil { Badge(text: "PRICE DROP", color: Theme.gold, textColor: .black) }
                    }
                    Spacer()
                    Button {
                        favorites.toggle(product)
                    } label: {
                        Image(systemName: isFavorite ? "heart.fill" : "heart")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(isFavorite ? Theme.sale : .white)
                            .frame(width: 32, height: 32)
                            .background(.black.opacity(0.55), in: Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(8)
            }
            .aspectRatio(3 / 4, contentMode: .fit)
            .clipped()

            VStack(alignment: .leading, spacing: 3) {
                Text(product.brand)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
                Text(product.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2, reservesSpace: true)
                PriceRow(price: product.price, was: previous ?? product.was, small: true, approx: product.converted)
                    .padding(.top, 2)
                if !product.sizes.isEmpty {
                    Text(product.sizes.joined(separator: " · "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if product.store != .ounass {
                    Text(product.store.name.uppercased())
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.gold)
                        .padding(.top, 1)
                }
            }
            .padding(10)
        }
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture(perform: onOpen)
        .contextMenu {
            Button {
                favorites.toggle(product)
            } label: {
                Label(isFavorite ? "Remove from favorites" : "Add to favorites",
                      systemImage: isFavorite ? "heart.slash" : "heart")
            }
            if let url = product.productURL {
                ShareLink(item: url, subject: Text(product.brand),
                          message: Text("\(product.brand) – \(product.name) for \(Money.format(product.price))")) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                Button { openURL(url) } label: {
                    Label("Open on Ounass", systemImage: "safari")
                }
            }
        }
    }
}

struct RemoteImage: View {
    let url: URL?

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            case .failure:
                Image(systemName: "photo").font(.title).foregroundStyle(.gray)
            default:
                ProgressView().tint(.gray)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }
}

struct Badge: View {
    let text: String
    let color: Color
    let textColor: Color

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(textColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(color, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

struct PriceRow: View {
    let price: Double
    let was: Double
    var small = false
    var approx = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(Money.format(price, approx: approx))
                .font(small ? .subheadline.weight(.bold) : .title3.weight(.bold))
            if was > price {
                Text(Money.format(was))
                    .font(small ? .caption2 : .subheadline)
                    .strikethrough()
                    .foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
}

// MARK: - Product page

struct ProductDetailView: View {
    let product: Product
    @EnvironmentObject private var favorites: FavoritesStore
    @Environment(\.openURL) private var openURL
    @State private var detail: ProductDetail?
    @State private var errorMessage: String?
    @State private var currentURL: URL?
    @State private var page = 0

    private var shareURL: URL? { currentURL ?? product.productURL }

    var body: some View {
        let isFavorite = favorites.contains(product)

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                gallery

                VStack(alignment: .leading, spacing: 6) {
                    Text(detail?.brand ?? product.brand)
                        .font(.title2.weight(.bold))
                    Text(detail?.name ?? product.name)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        PriceRow(price: detail?.price ?? product.price, was: detail?.was ?? product.was,
                                 approx: product.converted)
                        Badge(text: "-\(detail?.discount ?? product.discount)%", color: Theme.sale, textColor: .white)
                    }
                    .padding(.top, 4)
                    if let previous = Tracker.previousPrice(product.id) {
                        Text("Price dropped from \(Money.format(previous))")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.gold)
                    }
                }

                if let detail {
                    if detail.colors.count > 1 { colorsSection(detail) }
                    sizesSection(detail)
                    if !detail.description.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Details").font(.headline)
                            Text(detail.description)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else if let errorMessage {
                    Text(errorMessage).font(.footnote).foregroundStyle(.secondary)
                } else {
                    HStack { Spacer(); ProgressView(); Spacer() }.padding()
                }

                VStack(spacing: 10) {
                    if let url = shareURL {
                        Button {
                            openURL(url)
                        } label: {
                            Label("Buy on \(product.store.name)", systemImage: "bag")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.borderedProminent)
                        .foregroundStyle(.black)
                    }
                    Button {
                        favorites.toggle(product)
                    } label: {
                        Label(isFavorite ? "Saved to favorites" : "Add to favorites",
                              systemImage: isFavorite ? "heart.fill" : "heart")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if let url = shareURL {
                    ShareLink(item: url, subject: Text(product.brand),
                              message: Text("\(product.brand) – \(product.name) for \(Money.format(detail?.price ?? product.price))"))
                }
            }
        }
        .task(id: currentURL ?? product.productURL) { await load() }
    }

    private var gallery: some View {
        let images = detail?.images ?? []
        return ZStack {
            Color.white
            if images.isEmpty {
                RemoteImage(url: product.imageURL)
            } else {
                TabView(selection: $page) {
                    ForEach(Array(images.enumerated()), id: \.offset) { index, url in
                        RemoteImage(url: url).tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))
            }
        }
        .aspectRatio(3 / 4, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.top, 8)
    }

    private func colorsSection(_ detail: ProductDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Colours").font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(detail.colors) { color in
                        let selected = color.url?.path == (currentURL ?? product.productURL)?.path
                        Button {
                            if let url = color.url { currentURL = url; page = 0 }
                        } label: {
                            VStack(spacing: 4) {
                                Circle()
                                    .fill(Color(hex: color.hex))
                                    .frame(width: 30, height: 30)
                                    .overlay(Circle().stroke(selected ? Theme.gold : Color.gray.opacity(0.5),
                                                             lineWidth: selected ? 3 : 1))
                                    .opacity(color.inStock ? 1 : 0.35)
                                Text(color.label).font(.caption2).foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .frame(width: 64)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func sizesSection(_ detail: ProductDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sizes").font(.headline)
            if detail.sizes.isEmpty {
                Text("One size").font(.subheadline).foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 8)], spacing: 8) {
                    ForEach(detail.sizes) { size in
                        VStack(spacing: 2) {
                            Text(size.code)
                                .font(.subheadline.weight(.semibold))
                                .strikethrough(size.stock <= 0)
                            if size.stock <= 0 {
                                Text("Sold out").font(.system(size: 9))
                            } else if size.stock <= 2 {
                                Text("\(size.stock) left").font(.system(size: 9)).foregroundStyle(Theme.gold)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.3)))
                        .foregroundStyle(size.stock > 0 ? Color.primary : Color.secondary)
                    }
                }
            }
        }
    }

    private func load() async {
        guard product.store == .ounass else {
            detail = ProductDetail(brand: product.brand, name: product.name, price: product.price,
                                   was: product.was, discount: product.discount,
                                   images: product.imageURL.map { [$0] } ?? [],
                                   sizes: product.sizes.map { SizeStock(code: $0, stock: 3, urgency: nil) },
                                   description: "Full details, all photos and live stock are on \(product.store.name). Tap “Buy on \(product.store.name)” to open the item.",
                                   colors: [])
            return
        }
        guard let url = currentURL ?? product.productURL else {
            errorMessage = "No product link."
            return
        }
        errorMessage = nil
        do {
            let loaded = try await OunassAPI.fetchDetail(url)
            detail = loaded
            // Keep the saved favorite's price and sizes fresh.
            if currentURL == nil, favorites.contains(product), loaded.price > 0 {
                favorites.update(product.updated(price: loaded.price, was: loaded.was,
                                                 discount: loaded.discount, sizes: loaded.inStockSizes))
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Filters

struct FilterSheet: View {
    let title: String
    let localBrands: [String]
    let onApply: (SaleFilters) -> Void
    @State private var filters: SaleFilters
    @Environment(\.dismiss) private var dismiss

    init(title: String, filters: SaleFilters, localBrands: [String] = [],
         onApply: @escaping (SaleFilters) -> Void) {
        self.title = title
        self.localBrands = localBrands
        self.onApply = onApply
        _filters = State(initialValue: filters)
    }

    var body: some View {
        NavigationStack {
            Form { FilterFields(filters: $filters, localBrands: localBrands) }
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Reset") {
                            let sort = filters.sort
                            let category = filters.category
                            let shop = filters.store
                            filters = SaleFilters()
                            filters.sort = sort
                            filters.category = category
                            filters.store = shop
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Apply") {
                            onApply(filters)
                            dismiss()
                        }
                        .fontWeight(.bold)
                    }
                }
        }
    }
}

/// Filter sections, usable inside any Form (Sale filters and Alerts).
struct FilterFields: View {
    @Binding var filters: SaleFilters
    /// Brands seen on the loaded pages (for stores without a brand list).
    var localBrands: [String] = []
    @State private var brandOptions: [String] = SaleFilters.popularBrands

    /// Switching category clears the type, which belongs to the old category.
    private var categoryBinding: Binding<String> {
        Binding(
            get: { filters.category },
            set: { newValue in
                guard newValue != filters.category else { return }
                filters.category = newValue
                filters.subcategory = ""
            }
        )
    }

    var body: some View {
        Section("Category") {
            Picker("Category", selection: categoryBinding) {
                ForEach(SaleFilters.categories) { Text($0.label).tag($0.value) }
            }
            .pickerStyle(.segmented)
            Picker("Type", selection: $filters.subcategory) {
                Text(filters.category == "shoes" ? "All shoes" : "All clothing").tag("")
                ForEach(ItemType.types(for: filters.category)) { Text($0.label).tag($0.rawValue) }
            }
        }

        Section {
            NavigationLink {
                BrandPicker(selected: $filters.brands, options: brandOptions)
            } label: {
                HStack {
                    Text("Brands")
                    Spacer()
                    Text(filters.brands.isEmpty ? "Any" : filters.brands.joined(separator: ", "))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .task(id: filters.store.rawValue + "/" + filters.category + "/" + filters.subcategory) { await loadBrands() }

        if filters.store.usesAPI {
            Section("Colour") {
                ColorChips(selected: $filters.colors)
            }
        }

        if filters.category == "shoes" {
            Section("Shoe size (EU)") {
                ChipGrid(options: SaleFilters.shoeSizeOptions, selected: $filters.shoeSizes)
            }
        } else {
            Section("Clothing size") {
                ChipGrid(options: SaleFilters.clothingSizeOptions, selected: $filters.clothingSizes)
            }
        }

        Section("Discount") {
            Picker("Minimum discount", selection: $filters.minDiscount) {
                Text("Any").tag(0)
                ForEach(SaleFilters.discountSteps, id: \.self) { Text("\($0)% or more").tag($0) }
            }
        }

        Section {
            HStack {
                TextField("Min", text: priceText(\.minPrice))
                    .keyboardType(.decimalPad)
                Text("–").foregroundStyle(.secondary)
                TextField("Max", text: priceText(\.maxPrice))
                    .keyboardType(.decimalPad)
                Text("BHD").foregroundStyle(.secondary)
            }
        } header: {
            Text("Price")
        } footer: {
            Text(filters.store.usesAPI
                 ? "Tip: with a max price, sort by “Price: low to high” for the fastest results."
                 : "\(filters.store.name) filters are applied on your phone to the pages loaded so far. Converted prices are approximate.")
        }
    }

    private func priceText(_ keyPath: WritableKeyPath<SaleFilters, Double?>) -> Binding<String> {
        Binding(
            get: {
                guard let value = filters[keyPath: keyPath] else { return "" }
                return value.formatted(.number.grouping(.never).precision(.fractionLength(0...3)))
            },
            set: { text in
                filters[keyPath: keyPath] = text.isEmpty ? nil : NumberInput.parse(text)
            }
        )
    }

    private func loadBrands() async {
        let live: [String]
        if filters.store.usesAPI {
            live = (try? await OunassAPI.fetchBrands(category: filters.category,
                                                      subcategory: filters.subcategory)) ?? []
        } else {
            live = localBrands
        }
        var seen = Set<String>()
        brandOptions = (live + SaleFilters.popularBrands + filters.brands)
            .filter { seen.insert($0.lowercased()).inserted }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}

struct ChipGrid: View {
    let options: [String]
    @Binding var selected: [String]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 54), spacing: 8)], spacing: 8) {
            ForEach(options, id: \.self) { option in
                let on = selected.contains(option)
                Button {
                    if on { selected.removeAll { $0 == option } } else { selected.append(option) }
                } label: {
                    Text(option)
                        .font(.subheadline.weight(on ? .bold : .regular))
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background(on ? Theme.gold : Color.gray.opacity(0.18),
                                    in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .foregroundStyle(on ? Color.black : Color.primary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }
}

struct ColorChips: View {
    @Binding var selected: [String]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 60), spacing: 8)], spacing: 10) {
            ForEach(SaleFilters.colorOptions) { color in
                let on = selected.contains(color.id)
                Button {
                    if on { selected.removeAll { $0 == color.id } } else { selected.append(color.id) }
                } label: {
                    VStack(spacing: 4) {
                        swatch(color)
                            .frame(width: 28, height: 28)
                            .overlay(Circle().stroke(on ? Theme.gold : Color.gray.opacity(0.5),
                                                     lineWidth: on ? 3 : 1))
                        Text(color.name)
                            .font(.caption2.weight(on ? .bold : .regular))
                            .foregroundStyle(on ? Theme.gold : .secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder private func swatch(_ color: ColorOption) -> some View {
        if color.hex == "multi" {
            Circle().fill(AngularGradient(colors: [.red, .yellow, .green, .blue, .purple, .red],
                                          center: .center))
        } else {
            Circle().fill(Color(hex: color.hex))
        }
    }
}

struct BrandPicker: View {
    @Binding var selected: [String]
    let options: [String]
    @State private var query = ""

    private var filtered: [String] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty ? options : options.filter { $0.lowercased().contains(q) }
    }

    private func isOn(_ brand: String) -> Bool {
        selected.contains { $0.caseInsensitiveCompare(brand) == .orderedSame }
    }

    private func toggle(_ brand: String) {
        if isOn(brand) {
            selected.removeAll { $0.caseInsensitiveCompare(brand) == .orderedSame }
        } else {
            selected.append(brand)
        }
    }

    var body: some View {
        List {
            if !selected.isEmpty {
                Section("Selected") {
                    ForEach(selected, id: \.self) { brand in
                        row(brand)
                    }
                    Button("Clear all", role: .destructive) { selected = [] }
                }
            }
            let typed = query.trimmingCharacters(in: .whitespaces)
            if !typed.isEmpty && !options.contains(where: { $0.caseInsensitiveCompare(typed) == .orderedSame }) {
                Section {
                    Button("Add “\(typed)”") { toggle(typed); query = "" }
                }
            }
            Section(query.isEmpty ? "All brands on sale" : "Results") {
                ForEach(filtered, id: \.self) { brand in
                    row(brand)
                }
            }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search brands")
        .navigationTitle("Brands")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ brand: String) -> some View {
        Button {
            toggle(brand)
        } label: {
            HStack {
                Text(brand).foregroundStyle(.primary)
                Spacer()
                if isOn(brand) {
                    Image(systemName: "checkmark").foregroundStyle(Theme.gold)
                }
            }
        }
    }
}

// MARK: - Favorites tab

struct FavoritesView: View {
    @EnvironmentObject private var favorites: FavoritesStore
    @State private var path: [Product] = []

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if favorites.items.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "heart").font(.largeTitle)
                        Text("No favorites yet").font(.headline)
                        Text("Tap the heart on any item to save it here. Turn on Alerts to hear about price drops.")
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                    }
                    .foregroundStyle(.secondary)
                    .padding(32)
                } else {
                    ScrollView {
                        LazyVGrid(columns: gridColumns, spacing: 12) {
                            ForEach(favorites.items) { product in
                                ProductCard(product: product) { path.append(product) }
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .navigationTitle("Favorites")
            .navigationDestination(for: Product.self) { ProductDetailView(product: $0) }
            .onAppear { favorites.reload() }
        }
    }
}

// MARK: - Alerts tab

struct AlertsView: View {
    @EnvironmentObject private var favorites: FavoritesStore
    @State private var enabled = AlertSettings.enabled
    @State private var favoritesAlerts = AlertSettings.favoritesAlerts
    @State private var filters = AlertSettings.filters
    @State private var checking = false
    @State private var status = ""
    @State private var lastCheck = AlertSettings.lastCheck

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Notify me about new deals", isOn: $enabled)
                    Toggle("Favorites: price drops & low stock", isOn: $favoritesAlerts)
                } footer: {
                    Text("Sale Hunter checks Ounass' newest sale items in the background every few hours and notifies you when they match the filters below. Favorite alerts cover Ounass items. iOS decides the exact timing, so keep Background App Refresh on.")
                }

                FilterFields(filters: $filters)

                Section {
                    Button {
                        Task { await checkNow() }
                    } label: {
                        HStack {
                            Text("Check now")
                            Spacer()
                            if checking { ProgressView() }
                        }
                    }
                    .disabled(checking)
                    if !status.isEmpty {
                        Text(status).font(.footnote).foregroundStyle(.secondary)
                    }
                } footer: {
                    if let lastCheck {
                        Text("Last check: \(lastCheck.formatted(date: .abbreviated, time: .shortened))")
                    }
                }
            }
            .navigationTitle("Alerts")
            .onChange(of: enabled) { on in
                AlertSettings.enabled = on
                if on {
                    Task {
                        let granted = await AlertChecker.requestPermission()
                        if !granted {
                            status = "Notifications are off. Turn them on in Settings › Sale Hunter."
                        }
                        AlertChecker.scheduleNext()
                    }
                }
            }
            .onChange(of: favoritesAlerts) { AlertSettings.favoritesAlerts = $0 }
            .onChange(of: filters) { AlertSettings.filters = $0 }
        }
    }

    private func checkNow() async {
        checking = true
        status = ""
        do {
            let result = try await AlertChecker.check(notify: true)
            var lines: [String] = []
            if result.baseline {
                lines.append("Saved the current \(result.checked) newest items for these filters. You'll be notified about anything new from now on.")
            } else if result.found.isEmpty {
                lines.append("No new items since last time.")
            } else {
                lines.append("Found \(result.found.count) new item\(result.found.count == 1 ? "" : "s").")
            }
            if favoritesAlerts && !favorites.items.isEmpty {
                lines.append(result.favoriteChanges.isEmpty
                             ? "Favorites: no changes."
                             : "Favorites: \(result.favoriteChanges.count) update\(result.favoriteChanges.count == 1 ? "" : "s").")
            }
            status = lines.joined(separator: "\n")
            favorites.reload()
        } catch {
            status = error.localizedDescription
        }
        lastCheck = AlertSettings.lastCheck
        checking = false
    }
}


// MARK: - Store picker

struct StorePicker: View {
    @Binding var selection: Store

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Store.allCases) { shop in
                        let on = shop == selection
                        Button {
                            selection = shop
                        } label: {
                            Text(shop.name)
                                .font(.subheadline.weight(on ? .bold : .medium))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(on ? Theme.gold : Color.gray.opacity(0.18), in: Capsule())
                                .foregroundStyle(on ? Color.black : Color.primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
            Text(selection.blurb)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
        }
        .padding(.top, 4)
    }
}
