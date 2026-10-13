import SwiftUI

// MARK: - Sale tab

enum SortOption: String, CaseIterable, Identifiable {
    case featured = "Featured"
    case discount = "Biggest discount"
    case priceLow = "Price: low to high"
    case priceHigh = "Price: high to low"
    case newest = "New to you first"
    var id: String { rawValue }
}

private let gridColumns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

struct SaleView: View {
    @StateObject private var store = SaleStore()
    @State private var search = ""
    @State private var sort: SortOption = .featured
    @State private var showFilters = false

    private var shown: [Product] {
        var list = store.products
        let words = search.lowercased().split(separator: " ").map(String.init)
        if !words.isEmpty {
            list = list.filter { p in
                let hay = (p.brand + " " + p.name).lowercased()
                return words.allSatisfy { hay.contains($0) }
            }
        }
        switch sort {
        case .featured: break
        case .discount: list.sort { $0.discount > $1.discount }
        case .priceLow: list.sort { $0.price < $1.price }
        case .priceHigh: list.sort { $0.price > $1.price }
        case .newest:
            list.sort { (Tracker.isNew($0.id) ? 1 : 0) > (Tracker.isNew($1.id) ? 1 : 0) }
        }
        return list
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    summary
                    LazyVGrid(columns: gridColumns, spacing: 12) {
                        ForEach(shown) { ProductCard(product: $0) }
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
                        Picker("Sort", selection: $sort) {
                            ForEach(SortOption.allCases) { Text($0.rawValue).tag($0) }
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
            .sheet(isPresented: $showFilters) {
                FilterSheet(title: "Filters", filters: store.filters) { newFilters in
                    store.filters = newFilters
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
            HStack {
                Text("\(store.total.formatted()) men's items on sale")
                Spacer()
                if store.filters.activeCount > 0 {
                    Text("\(store.filters.activeCount) filter\(store.filters.activeCount == 1 ? "" : "s")")
                        .foregroundStyle(Theme.gold)
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
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
            if search.isEmpty {
                ProgressView()
                    .padding(32)
                    .id(store.products.count)
                    .onAppear { Task { await store.loadMore() } }
            } else {
                Button(store.isLoading ? "Loading…" : "Search more items") {
                    Task { await store.loadMore() }
                }
                .buttonStyle(.bordered)
                .padding(24)
            }
        } else if store.products.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "tag.slash").font(.title2)
                Text("No items match these filters.")
                if !store.filters.brand.isEmpty {
                    Text("Check the brand is spelled exactly as on Ounass.").font(.footnote)
                }
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
    @EnvironmentObject private var favorites: FavoritesStore
    @Environment(\.openURL) private var openURL

    var body: some View {
        let isFavorite = favorites.contains(product)
        let previous = Tracker.previousPrice(product.id)

        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .top) {
                Color.white
                AsyncImage(url: product.imageURL) { phase in
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

                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        badge("-\(product.discount)%", color: Theme.sale, text: .white)
                        if Tracker.isNew(product.id) { badge("NEW", color: Theme.fresh, text: .black) }
                        if previous != nil { badge("PRICE DROP", color: Theme.gold, text: .black) }
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
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(Money.format(product.price))
                        .font(.subheadline.weight(.bold))
                    Text(Money.format(previous ?? product.was))
                        .font(.caption2)
                        .strikethrough()
                        .foregroundStyle(.secondary)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.top, 2)
                if !product.sizes.isEmpty {
                    Text(product.sizes.joined(separator: " · "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(10)
        }
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture {
            if let url = product.productURL { openURL(url) }
        }
    }

    private func badge(_ label: String, color: Color, text: Color) -> some View {
        Text(label)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(text)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(color, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

// MARK: - Filters

struct FilterSheet: View {
    let title: String
    let onApply: (SaleFilters) -> Void
    @State private var filters: SaleFilters
    @Environment(\.dismiss) private var dismiss

    init(title: String, filters: SaleFilters, onApply: @escaping (SaleFilters) -> Void) {
        self.title = title
        self.onApply = onApply
        _filters = State(initialValue: filters)
    }

    var body: some View {
        NavigationStack {
            Form { FilterFields(filters: $filters) }
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Reset") { filters = SaleFilters() }
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

/// Filter sections, usable inside any Form.
struct FilterFields: View {
    @Binding var filters: SaleFilters

    var body: some View {
        Section("Discount") {
            Picker("Minimum discount", selection: $filters.minDiscount) {
                Text("Any").tag(0)
                ForEach(SaleFilters.discountSteps, id: \.self) { Text("\($0)% or more").tag($0) }
            }
        }
        Section("Category") {
            Picker("Category", selection: $filters.category) {
                ForEach(SaleFilters.categories, id: \.value) { Text($0.label).tag($0.value) }
            }
        }
        Section {
            HStack {
                TextField("Any brand", text: $filters.brand)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                Menu {
                    Button("Any brand") { filters.brand = "" }
                    ForEach(SaleFilters.popularBrands, id: \.self) { brand in
                        Button(brand) { filters.brand = brand }
                    }
                } label: {
                    Image(systemName: "list.bullet.circle")
                }
            }
        } header: {
            Text("Brand")
        } footer: {
            Text("Pick from the list or type the brand exactly as Ounass writes it.")
        }
        Section("Sizes") {
            Picker("Clothing size", selection: $filters.clothingSize) {
                Text("Any").tag("")
                ForEach(SaleFilters.clothingSizes, id: \.self) { Text($0).tag($0) }
            }
            Picker("Shoe size (EU)", selection: $filters.shoeSize) {
                Text("Any").tag("")
                ForEach(SaleFilters.shoeSizes, id: \.self) { Text($0).tag($0) }
            }
        }
    }
}

// MARK: - Favorites tab

struct FavoritesView: View {
    @EnvironmentObject private var favorites: FavoritesStore

    var body: some View {
        NavigationStack {
            Group {
                if favorites.items.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "heart").font(.largeTitle)
                        Text("No favorites yet").font(.headline)
                        Text("Tap the heart on any item to save it here.")
                            .font(.subheadline)
                    }
                    .foregroundStyle(.secondary)
                    .padding()
                } else {
                    ScrollView {
                        LazyVGrid(columns: gridColumns, spacing: 12) {
                            ForEach(favorites.items) { ProductCard(product: $0) }
                        }
                        .padding(16)
                    }
                }
            }
            .navigationTitle("Favorites")
        }
    }
}

// MARK: - Alerts tab

struct AlertsView: View {
    @State private var enabled = AlertSettings.enabled
    @State private var filters = AlertSettings.filters
    @State private var checking = false
    @State private var status = ""
    @State private var lastCheck = AlertSettings.lastCheck

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Notify me about new deals", isOn: $enabled)
                } footer: {
                    Text("Sale Hunter checks Ounass in the background every few hours and notifies you when new items match the filters below. iOS decides the exact timing, so keep Background App Refresh on.")
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
            .onChange(of: filters) { newValue in
                AlertSettings.filters = newValue
            }
        }
    }

    private func checkNow() async {
        checking = true
        status = ""
        do {
            let result = try await AlertChecker.check(notify: true)
            if result.baseline {
                status = "Saved \(result.checked) current items for these filters. You'll be notified about anything new from now on."
            } else if result.found.isEmpty {
                status = "Checked \(result.checked) items — nothing new since last time."
            } else {
                status = "Found \(result.found.count) new item\(result.found.count == 1 ? "" : "s")."
            }
        } catch {
            status = error.localizedDescription
        }
        lastCheck = AlertSettings.lastCheck
        checking = false
    }
}
