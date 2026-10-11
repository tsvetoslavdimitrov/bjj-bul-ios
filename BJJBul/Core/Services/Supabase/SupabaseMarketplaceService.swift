import Foundation
import Supabase

private struct PartnerEmbed: Decodable {
    let name: String
    let status: String
}

private struct ProductRow: Decodable {
    let id: UUID
    let partner_id: UUID
    let title_bg: String
    let title_en: String?
    let description_bg: String?
    let description_en: String?
    let category: String
    let price_eur: Double
    let compare_at_price: Double?
    let image_urls: [String]?
    let sizes: [String]?
    let stock: Int?
    let external_url: String?
    let fulfillment: String
    let active: Bool
    let partners: PartnerEmbed?

    var model: Product {
        Product(id: id, partnerId: partner_id, partnerName: partners?.name ?? "",
                partnerUnconfirmed: (partners?.status ?? "pending") != "approved",
                titleBg: title_bg, titleEn: title_en, descriptionBg: description_bg, descriptionEn: description_en,
                category: ProductCategory(rawValue: category) ?? .other, priceEUR: price_eur,
                compareAtPrice: compare_at_price, imageURLs: (image_urls ?? []).compactMap { URL(string: $0) },
                sizes: sizes ?? [], stock: stock, externalURL: external_url.flatMap { URL(string: $0) },
                fulfillment: Fulfillment(rawValue: fulfillment) ?? .orderRequest, active: active)
    }
}

private struct ProductUpsert: Encodable {
    let product: Product

    enum CodingKeys: String, CodingKey {
        case id, partner_id, title_bg, title_en, description_bg, description_en, category, price_eur,
             compare_at_price, image_urls, sizes, stock, external_url, fulfillment, active, updated_at
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(product.id, forKey: .id)
        try c.encode(product.partnerId, forKey: .partner_id)
        try c.encode(product.titleBg, forKey: .title_bg)
        try c.encode(product.titleEn, forKey: .title_en)
        try c.encode(product.descriptionBg, forKey: .description_bg)
        try c.encode(product.descriptionEn, forKey: .description_en)
        try c.encode(product.category.rawValue, forKey: .category)
        try c.encode(product.priceEUR, forKey: .price_eur)
        try c.encode(product.compareAtPrice, forKey: .compare_at_price)
        try c.encode(product.imageURLs.map { $0.absoluteString }, forKey: .image_urls)
        try c.encode(product.sizes, forKey: .sizes)
        try c.encode(product.stock, forKey: .stock)
        try c.encode(product.externalURL?.absoluteString, forKey: .external_url)
        try c.encode(product.fulfillment.rawValue, forKey: .fulfillment)
        try c.encode(product.active, forKey: .active)
        try c.encode(BGDate.iso(Date()), forKey: .updated_at)
    }
}

private struct PartnerRow: Decodable {
    let id: UUID
    let name: String
    let slug: String?
    let logo_url: String?
    let description: String?
    let website: String?
    let contact_email: String?
    let revolut_url: String?
    let commission_pct: Double
    let status: String
    let role: String?

    var model: Partner {
        Partner(id: id, name: name, slug: slug, logoURL: logo_url.flatMap { URL(string: $0) },
                description: description, website: website.flatMap { URL(string: $0) },
                contactEmail: contact_email, revolutURL: revolut_url.flatMap { URL(string: $0) },
                commissionPct: commission_pct, status: PartnerStatus(rawValue: status) ?? .pending, role: role)
    }
}

private struct OrderItemRow: Codable {
    let product_id: UUID?
    let title: String?
    let size: String?
    let qty: Int
    let price_eur: Double?
}

private struct OrderRow: Decodable {
    let id: UUID
    let partner_id: UUID
    let items: [OrderItemRow]
    let total_eur: Double
    let commission_amount: Double
    let status: String
    let payment_method: String
    let shipping_name: String
    let shipping_phone: String
    let delivery_type: String
    let shipping_address: String
    let notes: String?
    let reference: String?
    let created_at: String
    let partners: PartnerEmbed?

    var model: MarketplaceOrder {
        MarketplaceOrder(id: id, partnerId: partner_id, partnerName: partners?.name ?? "", buyerName: nil,
                         items: items.map { OrderItem(productId: $0.product_id, title: $0.title ?? "", size: $0.size,
                                                      qty: $0.qty, priceEUR: $0.price_eur ?? 0) },
                         totalEUR: total_eur, commissionAmount: commission_amount,
                         status: OrderStatus(rawValue: status) ?? .requested,
                         paymentMethod: OrderPaymentMethod(rawValue: payment_method) ?? .revolut,
                         shippingName: shipping_name, shippingPhone: shipping_phone,
                         deliveryType: DeliveryType(rawValue: delivery_type) ?? .address,
                         shippingAddress: shipping_address, notes: notes, reference: reference,
                         createdAt: DateParsing.date(from: created_at))
    }
}

private struct LedgerRow: Decodable {
    let month: String
    let orders: Int
    let sales_eur: Double
    let commission_eur: Double
    let paid_eur: Double
    let owed_eur: Double
    let clicks: Int
}

private struct CartItemParam: Encodable {
    let product_id: UUID
    let size: String?
    let qty: Int
}

private struct OrderParams: Encodable {
    let p_partner: UUID
    let p_items: [CartItemParam]
    let p_payment_method: String
    let p_shipping_name: String
    let p_shipping_phone: String
    let p_delivery_type: String
    let p_shipping_address: String
    let p_notes: String?
}

private struct PartnerInsert: Encodable {
    let name: String
    let description: String?
    let website: String?
    let contact_email: String
    let owner_user_id: UUID
    let status: String
}

private struct ProductIdParam: Encodable { let p_product: UUID }
private struct PartnerIdParam: Encodable { let p_partner: UUID }
private struct OrderStatusParams: Encodable {
    let p_order: UUID
    let p_status: String
}

struct SupabaseMarketplaceService: MarketplaceService {
    let client: SupabaseClient
    private let bucket = "product-media"
    private let productSelect = "*, partners(name, status)"
    private let orderSelect = "*, partners(name, status)"

    func products(category: ProductCategory?, search: String) async throws -> [Product] {
        var query = client.from("products").select(productSelect).eq("active", value: true)
        if let category {
            query = query.eq("category", value: category.rawValue)
        }
        let rows: [ProductRow] = try await query.order("created_at", ascending: false).limit(200).execute().value
        let needle = search.trimmingCharacters(in: .whitespaces).lowercased()
        let items = rows.map { $0.model }
        if needle.isEmpty { return items }
        return items.filter { item in
            item.titleBg.lowercased().contains(needle)
                || (item.titleEn ?? "").lowercased().contains(needle)
                || item.partnerName.lowercased().contains(needle)
        }
    }

    func products(partnerId: UUID) async throws -> [Product] {
        let rows: [ProductRow] = try await client.from("products").select(productSelect)
            .eq("partner_id", value: partnerId.uuidString)
            .order("created_at", ascending: false).execute().value
        return rows.map { $0.model }
    }

    func partner(id: UUID) async throws -> Partner? {
        let rows: [PartnerRow] = try await client.from("partners")
            .select("id, name, slug, logo_url, description, website, contact_email, revolut_url, commission_pct, status")
            .eq("id", value: id.uuidString).limit(1).execute().value
        return rows.first?.model
    }

    func trackAffiliateClick(productId: UUID) async throws -> URL {
        let text: String = try await client.rpc("track_affiliate_click", params: ProductIdParam(p_product: productId))
            .execute().value
        guard let url = URL(string: text) else { throw URLError(.badURL) }
        return url
    }

    func placeOrder(partnerId: UUID, items: [CartItem], draft: CheckoutDraft) async throws -> MarketplaceOrder {
        let notes = draft.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let params = OrderParams(p_partner: partnerId,
                                 p_items: items.map { CartItemParam(product_id: $0.product.id, size: $0.size, qty: $0.qty) },
                                 p_payment_method: draft.paymentMethod.rawValue,
                                 p_shipping_name: draft.shippingName, p_shipping_phone: draft.shippingPhone,
                                 p_delivery_type: draft.deliveryType.rawValue,
                                 p_shipping_address: draft.shippingAddress, p_notes: notes.isEmpty ? nil : notes)
        let orderId: UUID = try await client.rpc("create_marketplace_order", params: params).execute().value
        let rows: [OrderRow] = try await client.from("marketplace_orders").select(orderSelect)
            .eq("id", value: orderId.uuidString).limit(1).execute().value
        guard let row = rows.first else { throw URLError(.badServerResponse) }
        return row.model
    }

    func myOrders() async throws -> [MarketplaceOrder] {
        let userId = try await client.auth.session.user.id
        let rows: [OrderRow] = try await client.from("marketplace_orders").select(orderSelect)
            .eq("buyer_id", value: userId.uuidString)
            .order("created_at", ascending: false).execute().value
        return rows.map { $0.model }
    }

    func cancelOrder(id: UUID) async throws {
        try await setOrderStatus(orderId: id, status: .cancelled)
    }

    func applyAsPartner(_ application: PartnerApplication) async throws {
        let userId = try await client.auth.session.user.id
        let website = application.website.trimmingCharacters(in: .whitespaces)
        let description = application.description.trimmingCharacters(in: .whitespacesAndNewlines)
        let row = PartnerInsert(name: application.name.trimmingCharacters(in: .whitespaces),
                                description: description.isEmpty ? nil : description,
                                website: website.isEmpty ? nil : website,
                                contact_email: application.contactEmail.trimmingCharacters(in: .whitespaces),
                                owner_user_id: userId, status: "pending")
        try await client.from("partners").insert(row).execute()
    }

    func myPartners() async throws -> [Partner] {
        let rows: [PartnerRow] = try await client.rpc("my_partners").execute().value
        return rows.map { $0.model }
    }

    func saveProduct(_ product: Product) async throws {
        try await client.from("products").upsert(ProductUpsert(product: product)).execute()
    }

    func deleteProduct(id: UUID) async throws {
        try await client.from("products").delete().eq("id", value: id.uuidString).execute()
    }

    func uploadProductImage(partnerId: UUID, jpegData: Data) async throws -> URL {
        let path = "\(partnerId.uuidString.lowercased())/\(UUID().uuidString.lowercased()).jpg"
        _ = try await client.storage.from(bucket)
            .upload(path, data: jpegData, options: FileOptions(contentType: "image/jpeg"))
        return try client.storage.from(bucket).getPublicURL(path: path)
    }

    func partnerOrders(partnerId: UUID) async throws -> [MarketplaceOrder] {
        let rows: [OrderRow] = try await client.from("marketplace_orders").select(orderSelect)
            .eq("partner_id", value: partnerId.uuidString)
            .order("created_at", ascending: false).execute().value
        return rows.map { $0.model }
    }

    func setOrderStatus(orderId: UUID, status: OrderStatus) async throws {
        try await client.rpc("set_marketplace_order_status",
                             params: OrderStatusParams(p_order: orderId, p_status: status.rawValue)).execute()
    }

    func ledger(partnerId: UUID) async throws -> [LedgerMonth] {
        let rows: [LedgerRow] = try await client.rpc("partner_ledger", params: PartnerIdParam(p_partner: partnerId))
            .execute().value
        return rows.compactMap { (row: LedgerRow) -> LedgerMonth? in
            guard let month = EventDates.date(from: row.month) else { return nil }
            return LedgerMonth(month: month, orders: row.orders, salesEUR: row.sales_eur,
                               commissionEUR: row.commission_eur, paidEUR: row.paid_eur,
                               owedEUR: row.owed_eur, clicks: row.clicks)
        }
    }
}
