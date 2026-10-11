import Foundation

enum ProductCategory: String, CaseIterable, Hashable {
    case gi, rashguard, shorts, belts, gear, supplements, apparel, other

    var localizedKey: String { "shop.cat.\(rawValue)" }

    var symbol: String {
        switch self {
        case .gi: return "figure.martial.arts"
        case .rashguard: return "tshirt.fill"
        case .shorts: return "figure.run"
        case .belts: return "line.3.horizontal"
        case .gear: return "bag.fill"
        case .supplements: return "leaf.fill"
        case .apparel: return "tshirt"
        case .other: return "shippingbox.fill"
        }
    }
}

enum Fulfillment: String, CaseIterable, Hashable {
    case affiliateLink = "affiliate_link"
    case orderRequest = "order_request"

    var localizedKey: String { "shop.fulfillment.\(rawValue)" }
}

enum PartnerStatus: String, Hashable {
    case pending, approved, suspended
}

struct Partner: Identifiable, Hashable {
    let id: UUID
    var name: String
    var slug: String?
    var logoURL: URL?
    var description: String?
    var website: URL?
    var contactEmail: String?
    var revolutURL: URL?
    var commissionPct: Double
    var status: PartnerStatus
    /// For "My partner store": owner / staff / applicant.
    var role: String? = nil

    var isUnconfirmed: Bool { status != .approved }
}

struct Product: Identifiable, Hashable {
    let id: UUID
    var partnerId: UUID
    var partnerName: String
    var partnerUnconfirmed: Bool
    var titleBg: String
    var titleEn: String?
    var descriptionBg: String?
    var descriptionEn: String?
    var category: ProductCategory
    var priceEUR: Double
    var compareAtPrice: Double?
    var imageURLs: [URL]
    var sizes: [String]
    var stock: Int?
    var externalURL: URL?
    var fulfillment: Fulfillment
    var active: Bool

    func title(bulgarian: Bool) -> String {
        if bulgarian { return titleBg }
        if let titleEn, !titleEn.isEmpty { return titleEn }
        return titleBg
    }

    func details(bulgarian: Bool) -> String? {
        let text = bulgarian ? (descriptionBg ?? descriptionEn) : (descriptionEn ?? descriptionBg)
        guard let text, !text.isEmpty else { return nil }
        return text
    }

    var isOutOfStock: Bool { (stock ?? 1) <= 0 }

    static func new(partnerId: UUID) -> Product {
        Product(id: UUID(), partnerId: partnerId, partnerName: "", partnerUnconfirmed: false, titleBg: "",
                titleEn: nil, descriptionBg: nil, descriptionEn: nil, category: .rashguard, priceEUR: 0,
                compareAtPrice: nil, imageURLs: [], sizes: [], stock: nil, externalURL: nil,
                fulfillment: .orderRequest, active: true)
    }
}

struct CartItem: Identifiable, Hashable {
    var id: String { product.id.uuidString + "-" + (size ?? "") }
    var product: Product
    var size: String?
    var qty: Int

    var lineTotal: Double { product.priceEUR * Double(qty) }
}

enum OrderStatus: String, CaseIterable, Hashable {
    case requested, confirmed, paid, shipped, completed, cancelled

    var localizedKey: String { "order.status.\(rawValue)" }

    var next: OrderStatus? {
        switch self {
        case .requested: return .confirmed
        case .confirmed: return .paid
        case .paid: return .shipped
        case .shipped: return .completed
        case .completed, .cancelled: return nil
        }
    }
}

enum OrderPaymentMethod: String, CaseIterable, Hashable {
    case revolut, cash, card

    var localizedKey: String { "order.pay.\(rawValue)" }
}

enum DeliveryType: String, CaseIterable, Hashable {
    case econtOffice = "econt_office"
    case speedyOffice = "speedy_office"
    case address

    var localizedKey: String { "order.delivery.\(rawValue)" }
}

struct OrderItem: Hashable {
    var productId: UUID?
    var title: String
    var size: String?
    var qty: Int
    var priceEUR: Double
}

struct MarketplaceOrder: Identifiable, Hashable {
    let id: UUID
    var partnerId: UUID
    var partnerName: String
    var buyerName: String?
    var items: [OrderItem]
    var totalEUR: Double
    var commissionAmount: Double
    var status: OrderStatus
    var paymentMethod: OrderPaymentMethod
    var shippingName: String
    var shippingPhone: String
    var deliveryType: DeliveryType
    var shippingAddress: String
    var notes: String?
    var reference: String?
    var createdAt: Date
}

struct CheckoutDraft: Hashable {
    var shippingName = ""
    var shippingPhone = ""
    var deliveryType: DeliveryType = .econtOffice
    var shippingAddress = ""
    var paymentMethod: OrderPaymentMethod = .revolut
    var notes = ""

    var isValid: Bool {
        !shippingName.trimmingCharacters(in: .whitespaces).isEmpty
            && shippingPhone.trimmingCharacters(in: .whitespaces).count >= 6
            && !shippingAddress.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

struct PartnerApplication: Hashable {
    var name = ""
    var description = ""
    var website = ""
    var contactEmail = ""
}

struct LedgerMonth: Identifiable, Hashable {
    var id: Date { month }
    var month: Date
    var orders: Int
    var salesEUR: Double
    var commissionEUR: Double
    var paidEUR: Double
    var owedEUR: Double
    var clicks: Int
}

enum PriceText {
    static func eur(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.locale = Locale.current
        let number = formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
        return number + " €"
    }
}
