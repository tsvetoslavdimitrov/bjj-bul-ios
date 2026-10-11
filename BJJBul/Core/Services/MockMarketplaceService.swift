import Foundation

/// SAMPLE marketplace data (fictional stores, no real brands). Used for previews and demo mode.
enum MockMarketplaceData {
    static let partner1Id = UUID(uuidString: "00000000-0000-0000-0000-000000000501")!
    static let partner2Id = UUID(uuidString: "00000000-0000-0000-0000-000000000502")!

    static let partners: [Partner] = [
        Partner(id: partner1Id, name: "Sample Fightwear", slug: "sample-fightwear", logoURL: nil,
                description: "Sample store – fictional data for the demo.", website: nil,
                contactEmail: "store@example.com", revolutURL: URL(string: "https://revolut.me/samplestore"),
                commissionPct: 10, status: .approved, role: "owner"),
        Partner(id: partner2Id, name: "Sample Grappling Co.", slug: "sample-grappling", logoURL: nil,
                description: "Second sample store (unconfirmed).", website: nil, contactEmail: nil,
                revolutURL: nil, commissionPct: 10, status: .pending, role: nil),
    ]

    static func make(_ partner: Partner, _ bg: String, _ en: String, _ category: ProductCategory, _ price: Double,
                     compare: Double? = nil, sizes: [String] = [], stock: Int? = 10,
                     fulfillment: Fulfillment = .orderRequest, image: URL? = nil) -> Product {
        Product(id: UUID(), partnerId: partner.id, partnerName: partner.name, partnerUnconfirmed: partner.isUnconfirmed,
                titleBg: bg, titleEn: en, descriptionBg: "Примерен продукт (демо данни).",
                descriptionEn: "Sample product (demo data).", category: category, priceEUR: price,
                compareAtPrice: compare, imageURLs: image.map { [$0] } ?? [], sizes: sizes, stock: stock,
                externalURL: fulfillment == .affiliateLink ? URL(string: "https://example.com/sample-product") : nil,
                fulfillment: fulfillment, active: true)
    }

    static func products(images: [ProductCategory: URL] = [:]) -> [Product] {
        let a = partners[0]
        let b = partners[1]
        return [
            make(a, "Примерно ги Classic", "Sample Gi Classic", .gi, 120, compare: 140,
                 sizes: ["A1", "A2", "A3", "A4"], image: images[.gi]),
            make(a, "Примерен рашгард Ranked", "Sample Ranked Rashguard", .rashguard, 45,
                 sizes: ["S", "M", "L", "XL"], image: images[.rashguard]),
            make(a, "Примерни шорти No-Gi", "Sample No-Gi Shorts", .shorts, 40, sizes: ["S", "M", "L"], image: images[.shorts]),
            make(a, "Примерен колан", "Sample Belt", .belts, 25, sizes: ["A1", "A2", "A3"], image: images[.belts]),
            make(b, "Примерна протектор за уста", "Sample Mouthguard", .gear, 15, fulfillment: .affiliateLink,
                 image: images[.gear]),
            make(b, "Примерен суроватъчен протеин", "Sample Whey Protein", .supplements, 35, compare: 42,
                 fulfillment: .affiliateLink, image: images[.supplements]),
            make(b, "Примерна тениска", "Sample Tee", .apparel, 22, sizes: ["S", "M", "L", "XL"], stock: 0,
                 fulfillment: .affiliateLink, image: images[.apparel]),
        ]
    }
}

final class MockMarketplaceService: MarketplaceService {
    private var items: [Product]
    private var orders: [MarketplaceOrder] = []
    private var partners: [Partner] = MockMarketplaceData.partners

    init(products: [Product] = MockMarketplaceData.products(), sampleOrders: Bool = false) {
        items = products
        if sampleOrders {
            orders = Self.sampleOrders(products: products)
        }
    }

    /// SAMPLE orders for the partner dashboard.
    static func sampleOrders(products: [Product]) -> [MarketplaceOrder] {
        let ownProducts = products.filter { $0.partnerId == MockMarketplaceData.partner1Id }
        let names = ["Sample Buyer A.", "Sample Buyer B.", "Sample Buyer C.", "Sample Buyer D."]
        let statuses: [OrderStatus] = [.requested, .confirmed, .shipped, .completed]
        var result: [MarketplaceOrder] = []
        for index in 0..<names.count {
            guard !ownProducts.isEmpty else { break }
            let product = ownProducts[index % ownProducts.count]
            let qty = index == 2 ? 2 : 1
            let total = product.priceEUR * Double(qty)
            result.append(MarketplaceOrder(id: UUID(), partnerId: product.partnerId, partnerName: product.partnerName,
                                           buyerName: names[index],
                                           items: [OrderItem(productId: product.id, title: product.titleEn ?? product.titleBg,
                                                             size: product.sizes.first, qty: qty, priceEUR: product.priceEUR)],
                                           totalEUR: total, commissionAmount: (total * 0.1 * 100).rounded() / 100,
                                           status: statuses[index], paymentMethod: index % 2 == 0 ? .revolut : .cash,
                                           shippingName: names[index], shippingPhone: "+359 88 000 000\(index)",
                                           deliveryType: index == 1 ? .speedyOffice : .econtOffice,
                                           shippingAddress: "Sample office, Sofia", notes: nil,
                                           reference: "BJJ-SAMPLE\(index)",
                                           createdAt: Date().addingTimeInterval(-Double(index) * 86400 * 3)))
        }
        return result
    }

    func products(category: ProductCategory?, search: String) async throws -> [Product] {
        let needle = search.trimmingCharacters(in: .whitespaces).lowercased()
        return items.filter { item in
            if !item.active { return false }
            if let category, item.category != category { return false }
            if needle.isEmpty { return true }
            return item.titleBg.lowercased().contains(needle) || (item.titleEn ?? "").lowercased().contains(needle)
                || item.partnerName.lowercased().contains(needle)
        }
    }

    func products(partnerId: UUID) async throws -> [Product] { items.filter { $0.partnerId == partnerId } }

    func partner(id: UUID) async throws -> Partner? { partners.first { $0.id == id } }

    func trackAffiliateClick(productId: UUID) async throws -> URL {
        let base = items.first { $0.id == productId }?.externalURL?.absoluteString ?? "https://example.com"
        let separator = base.contains("?") ? "&" : "?"
        let tracked = base + separator + "ref=bjjbul-sample&utm_source=bjjbul&utm_medium=app&utm_campaign=marketplace"
        return URL(string: tracked) ?? URL(string: "https://example.com")!
    }

    func placeOrder(partnerId: UUID, items cart: [CartItem], draft: CheckoutDraft) async throws -> MarketplaceOrder {
        let total = cart.reduce(0) { $0 + $1.lineTotal }
        let name = partners.first { $0.id == partnerId }?.name ?? ""
        let order = MarketplaceOrder(id: UUID(), partnerId: partnerId, partnerName: name, buyerName: draft.shippingName,
                                     items: cart.map { OrderItem(productId: $0.product.id, title: $0.product.titleEn ?? $0.product.titleBg,
                                                                 size: $0.size, qty: $0.qty, priceEUR: $0.product.priceEUR) },
                                     totalEUR: total, commissionAmount: (total * 10).rounded() / 100,
                                     status: .requested, paymentMethod: draft.paymentMethod,
                                     shippingName: draft.shippingName, shippingPhone: draft.shippingPhone,
                                     deliveryType: draft.deliveryType, shippingAddress: draft.shippingAddress,
                                     notes: draft.notes, reference: "BJJ-MOCK\(orders.count + 1)", createdAt: Date())
        orders.insert(order, at: 0)
        return order
    }

    func myOrders() async throws -> [MarketplaceOrder] { orders.filter { $0.buyerName != nil } }

    func cancelOrder(id: UUID) async throws { try await setOrderStatus(orderId: id, status: .cancelled) }

    func applyAsPartner(_ application: PartnerApplication) async throws {
        partners.append(Partner(id: UUID(), name: application.name, slug: nil, logoURL: nil,
                                description: application.description, website: URL(string: application.website),
                                contactEmail: application.contactEmail, revolutURL: nil, commissionPct: 10,
                                status: .pending, role: "applicant"))
    }

    func myPartners() async throws -> [Partner] { partners.filter { $0.role != nil } }

    func saveProduct(_ product: Product) async throws {
        if let index = items.firstIndex(where: { $0.id == product.id }) {
            items[index] = product
        } else {
            var copy = product
            copy.partnerName = partners.first { $0.id == product.partnerId }?.name ?? ""
            items.insert(copy, at: 0)
        }
    }

    func deleteProduct(id: UUID) async throws { items.removeAll { $0.id == id } }

    func uploadProductImage(partnerId: UUID, jpegData: Data) async throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
        try jpegData.write(to: url)
        return url
    }

    func partnerOrders(partnerId: UUID) async throws -> [MarketplaceOrder] { orders.filter { $0.partnerId == partnerId } }

    func setOrderStatus(orderId: UUID, status: OrderStatus) async throws {
        if let index = orders.firstIndex(where: { $0.id == orderId }) {
            orders[index].status = status
        }
    }

    /// SAMPLE monthly numbers.
    func ledger(partnerId: UUID) async throws -> [LedgerMonth] {
        let cal = Calendar.bulgaria
        let comps = cal.dateComponents([.year, .month], from: Date())
        let thisMonth = cal.date(from: comps) ?? Date()
        let sales: [Double] = [610, 845, 720, 980, 1130, 905]
        var result: [LedgerMonth] = []
        for (offset, value) in sales.enumerated() {
            guard let month = cal.date(byAdding: .month, value: -offset, to: thisMonth) else { continue }
            let commission = (value * 10).rounded() / 100
            let paid = offset == 0 ? 0 : commission
            result.append(LedgerMonth(month: month, orders: Int(value / 55), salesEUR: value, commissionEUR: commission,
                                      paidEUR: paid, owedEUR: commission - paid, clicks: 120 + offset * 17))
        }
        return result
    }
}
