import Foundation

enum GymRole: String, CaseIterable, Hashable {
    case owner, coach, student

    var localizedKey: String { "gymrole.\(rawValue)" }
    var isStaff: Bool { self != .student }
}

enum MemberStatus: String, Hashable {
    case pending, active, removed

    var localizedKey: String { "memberstatus.\(rawValue)" }
}

struct MyGym: Identifiable, Hashable {
    var id: UUID { gymId }
    let gymId: UUID
    var name: String
    var slug: String
    var role: GymRole
    var status: MemberStatus
    var hasAccess: Bool
}

struct RosterMember: Identifiable, Hashable {
    var id: UUID { memberId }
    let memberId: UUID
    let userId: UUID
    var displayName: String
    var avatarURL: URL?
    var belt: Belt
    var stripes: Int
    var role: GymRole
    var status: MemberStatus
    var membershipId: UUID?
}

enum MembershipPeriod: String, CaseIterable, Hashable {
    case monthly, quarterly, yearly, dropIn = "drop_in", pack

    var localizedKey: String { "membership.period.\(rawValue)" }
}

struct Membership: Identifiable, Hashable {
    let id: UUID
    let gymId: UUID
    var name: String
    var price: Double
    var currency: String
    var period: MembershipPeriod
    var active: Bool
}

enum MemberPaymentMethod: String, CaseIterable, Hashable {
    case cash, revolut, card

    var localizedKey: String { "paymethod.\(rawValue)" }
}

struct PaymentStatusRow: Identifiable, Hashable {
    var id: UUID { userId }
    let userId: UUID
    var displayName: String
    var membershipName: String?
    var price: Double?
    var paid: Bool
    var paidAmount: Double
    var lastPaidAt: Date?
}

struct MemberPaymentDraft {
    var gymId: UUID
    var userId: UUID
    var membershipId: UUID?
    var amount: Double
    var method: MemberPaymentMethod
    var note: String
}

enum SubscriptionStatus: String, Hashable {
    case trialing, active, pastDue = "past_due", cancelled

    var localizedKey: String { "subscription.status.\(rawValue)" }
}

struct BJJBulPlan: Identifiable, Hashable {
    let id: UUID
    var code: String
    var name: String
    var priceMonthlyEUR: Double
    var features: [String]
}

struct GymSubscription: Hashable {
    var status: SubscriptionStatus
    var planId: UUID?
    var trialEndsAt: Date?
    var currentPeriodEnd: Date?
    var method: String?

    /// Mirrors gym_has_access() in SQL.
    var hasAccess: Bool {
        let now = Date()
        switch status {
        case .trialing: return (trialEndsAt ?? now) >= now
        case .active: return (currentPeriodEnd ?? now) >= now
        default: return false
        }
    }
}

struct GymClaimDraft {
    var gymId: UUID
    var role: GymRole
    var message: String
    var contact: String
}

struct GymProfileDraft {
    var gymId: UUID
    var name: String
    var address: String
    var phone: String
    var email: String
    var website: String
    var instagram: String
    var facebook: String
    var affiliation: String
    var priceDropIn: Decimal?
    var priceMonthly: Decimal?
    var priceKids: Decimal?
    var hasKids: Bool
    var hasWomenOnly: Bool
    var photoURLs: [URL]

    init(gym: Gym) {
        gymId = gym.id
        name = gym.name
        address = gym.address
        phone = gym.phone ?? ""
        email = gym.email ?? ""
        website = gym.website?.absoluteString ?? ""
        instagram = gym.instagram ?? ""
        facebook = gym.facebook ?? ""
        affiliation = gym.affiliation ?? ""
        priceDropIn = gym.priceDropIn
        priceMonthly = gym.priceMonthly
        priceKids = gym.priceKids
        hasKids = gym.hasKids
        hasWomenOnly = gym.hasWomenOnly
        photoURLs = gym.photoURLs
    }
}

// MARK: - Student payments (0011)

enum PaymentPeriodStatus: String, Hashable {
    case paid, due, overdue

    var localizedKey: String { "mypay.status.\(rawValue)" }
}

struct StudentMembership: Identifiable, Hashable {
    var id: UUID { gymId }
    let gymId: UUID
    var gymName: String
    var gymSlug: String
    var revolutURL: URL?
    var membershipId: UUID?
    var membershipName: String?
    var price: Double?
    var currency: String
    var period: MembershipPeriod
    var paidUntil: Date?
    var nextDue: Date?
    var status: PaymentPeriodStatus
    var pendingClaims: Int

    /// Month the next payment is for (the next due date's month, or this month).
    var periodMonth: Date { nextDue ?? Date() }

    /// "<gym-slug>-<short user id>-<YYYY-MM>"
    func reference(userId: UUID) -> String {
        let short = String(userId.uuidString.lowercased().prefix(6))
        return "\(gymSlug)-\(short)-\(String(EventDates.string(from: periodMonth).prefix(7)))"
    }
}

struct PaymentRecord: Identifiable, Hashable {
    let id: UUID
    var amount: Double
    var currency: String
    var method: MemberPaymentMethod
    var paidAt: Date
    var periodMonth: Date?
}

struct PaymentClaimDraft {
    var gymId: UUID
    var membershipId: UUID?
    var periodMonth: Date
    var amount: Double?
    var method: MemberPaymentMethod
    var reference: String
    var note: String
}

struct PaymentClaim: Identifiable, Hashable {
    let id: UUID
    let userId: UUID
    var displayName: String
    var periodMonth: Date?
    var amount: Double?
    var method: MemberPaymentMethod
    var reference: String?
    var note: String?
    var createdAt: Date
}
