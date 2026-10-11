import SwiftUI

enum ShopLocale {
    static var isBulgarian: Bool { Locale.current.language.languageCode?.identifier == "bg" }
}

/// Category placeholder or the product image.
struct ProductImageView: View {
    let url: URL?
    let category: ProductCategory
    var height: CGFloat = 150

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color.gray.opacity(0.25), Color.gray.opacity(0.1)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            if let url {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .clipped()
    }

    private var placeholder: some View {
        Image(systemName: category.symbol)
            .font(.system(size: height * 0.3))
            .foregroundStyle(.secondary)
    }
}

struct UnconfirmedPartnerBadge: View {
    var body: some View {
        Text("shop.unconfirmed")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.orange.opacity(0.18), in: Capsule())
            .foregroundStyle(.orange)
    }
}

struct PriceView: View {
    let price: Double
    let compareAt: Double?

    var body: some View {
        HStack(spacing: 6) {
            Text(PriceText.eur(price)).font(.headline)
            if let compareAt, compareAt > price {
                Text(PriceText.eur(compareAt))
                    .font(.caption)
                    .strikethrough()
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct ProductCardView: View {
    let product: Product

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ProductImageView(url: product.imageURLs.first, category: product.category, height: 150)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            Text(product.title(bulgarian: ShopLocale.isBulgarian))
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .foregroundStyle(.primary)
            PriceView(price: product.priceEUR, compareAt: product.compareAtPrice)
            HStack(spacing: 4) {
                Text(product.partnerName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if product.partnerUnconfirmed {
                    UnconfirmedPartnerBadge()
                }
            }
            if product.fulfillment == .affiliateLink {
                Label("shop.external", systemImage: "arrow.up.right.square")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .multilineTextAlignment(.leading)
    }
}

/// Product grid. Push it inside an existing NavigationStack (Explore toolbar, Profile row).
struct MarketplaceView: View {
    @Environment(AppServices.self) private var services
    @State private var products: [Product] = []
    @State private var category: ProductCategory?
    @State private var search = ""
    @State private var isLoading = true
    @State private var errorMessage: String?

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                chips
                if let errorMessage {
                    Text(errorMessage).font(.footnote).foregroundStyle(.red).padding(.horizontal)
                }
                if isLoading && products.isEmpty {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                } else if products.isEmpty {
                    ContentUnavailableView("shop.empty", systemImage: "bag")
                } else {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(products) { product in
                            NavigationLink(value: product) {
                                ProductCardView(product: product)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
                Text("shop.disclaimer")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding()
            }
        }
        .navigationTitle("shop.title")
        .searchable(text: $search, prompt: Text("shop.search"))
        .navigationDestination(for: Product.self) { product in
            ProductDetailView(product: product)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    CartView()
                } label: {
                    cartLabel
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    NavigationLink {
                        MyOrdersView()
                    } label: {
                        Label("shop.myOrders", systemImage: "shippingbox")
                    }
                    NavigationLink {
                        MyPartnerStoresView()
                    } label: {
                        Label("partner.myStore", systemImage: "storefront")
                    }
                    NavigationLink {
                        BecomePartnerView()
                    } label: {
                        Label("partner.become", systemImage: "person.crop.circle.badge.plus")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .task(id: reloadKey) {
            await load()
        }
        .refreshable {
            await load()
        }
    }

    private var reloadKey: String { (category?.rawValue ?? "all") + "|" + search }

    private var cartLabel: some View {
        let count = services.cart.reduce(0) { $0 + $1.qty }
        return ZStack(alignment: .topTrailing) {
            Image(systemName: "cart")
            if count > 0 {
                Text("\(count)")
                    .font(.caption2.bold())
                    .foregroundStyle(.white)
                    .padding(4)
                    .background(Color.red, in: Circle())
                    .offset(x: 8, y: -8)
            }
        }
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(title: Text("shop.cat.all"), selected: category == nil) { category = nil }
                ForEach(ProductCategory.allCases, id: \.self) { item in
                    chip(title: Text(LocalizedStringKey(item.localizedKey)), selected: category == item) {
                        category = item
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    private func chip(title: Text, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            title
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(selected ? Color.accentColor : Color.gray.opacity(0.15), in: Capsule())
                .foregroundStyle(selected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }

    @MainActor
    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            products = try await services.marketplace.products(category: category, search: search)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct ProductDetailView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.openURL) private var openURL
    let product: Product

    @State private var size: String?
    @State private var qty = 1
    @State private var partner: Partner?
    @State private var added = false
    @State private var errorMessage: String?
    @State private var isOpening = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                gallery
                VStack(alignment: .leading, spacing: 8) {
                    Text(product.title(bulgarian: ShopLocale.isBulgarian))
                        .font(.title2.bold())
                    PriceView(price: product.priceEUR, compareAt: product.compareAtPrice)
                    HStack(spacing: 6) {
                        Image(systemName: "storefront")
                        Text(product.partnerName)
                        if product.partnerUnconfirmed {
                            UnconfirmedPartnerBadge()
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    if product.partnerUnconfirmed {
                        Text("shop.unconfirmed.note")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if !product.sizes.isEmpty {
                    sizePicker
                }
                if let details = product.details(bulgarian: ShopLocale.isBulgarian) {
                    Text(details).font(.body)
                }
                actions
                if let errorMessage {
                    Text(errorMessage).font(.footnote).foregroundStyle(.red)
                }
            }
            .padding()
        }
        .navigationTitle(product.partnerName)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            partner = try? await services.marketplace.partner(id: product.partnerId)
            if size == nil { size = product.sizes.first }
        }
    }

    private var gallery: some View {
        Group {
            if product.imageURLs.count > 1 {
                TabView {
                    ForEach(product.imageURLs, id: \.self) { url in
                        ProductImageView(url: url, category: product.category, height: 320)
                    }
                }
                .tabViewStyle(.page)
                .frame(height: 320)
            } else {
                ProductImageView(url: product.imageURLs.first, category: product.category, height: 320)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var sizePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("shop.size").font(.subheadline.weight(.semibold))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(product.sizes, id: \.self) { item in
                        Button {
                            size = item
                        } label: {
                            Text(item)
                                .font(.subheadline.weight(.medium))
                                .frame(minWidth: 44)
                                .padding(.vertical, 8)
                                .background(size == item ? Color.accentColor : Color.gray.opacity(0.15),
                                            in: RoundedRectangle(cornerRadius: 8))
                                .foregroundStyle(size == item ? Color.white : Color.primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var actions: some View {
        if product.fulfillment == .affiliateLink {
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    Task { await openAffiliate() }
                } label: {
                    Label("shop.buyOnSite", systemImage: "safari")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isOpening || product.externalURL == nil)
                Text("shop.affiliate.note")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Stepper(value: $qty, in: 1...20) {
                    Text(String(format: NSLocalizedString("shop.qty %lld", comment: ""), qty))
                }
                Button {
                    services.addToCart(product, size: size, qty: qty)
                    added = true
                } label: {
                    Label("shop.addToCart", systemImage: "cart.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(product.isOutOfStock || (!product.sizes.isEmpty && size == nil))
                if product.isOutOfStock {
                    Text("shop.outOfStock").font(.caption).foregroundStyle(.red)
                }
                if added {
                    NavigationLink {
                        CartView()
                    } label: {
                        Label("shop.goToCart", systemImage: "cart")
                    }
                }
                Text("shop.order.note")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @MainActor
    private func openAffiliate() async {
        isOpening = true
        defer { isOpening = false }
        do {
            let url = try await services.marketplace.trackAffiliateClick(productId: product.id)
            openURL(url)
        } catch {
            // Logging failed: still let the user reach the shop.
            if let url = product.externalURL {
                openURL(url)
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }
}
