import Foundation

struct MemberQR: Hashable {
    var token: String
    var expiresAt: Date
    var memberCode: String
    var hasPin: Bool

    /// Rotating payload shown as a QR code.
    var payload: String { "bjjbul:t:\(token)" }
    /// Static fallback (printed card / screenshot).
    var staticPayload: String { "bjjbul:c:\(memberCode)" }
}

struct KioskMember: Identifiable, Hashable {
    var id: UUID { userId }
    let userId: UUID
    var shortName: String
    var belt: Belt?
    var hasPin: Bool
}

enum KioskCheckInStatus: String {
    case ok, unpaid
    case noCredits = "no_credits"
    case badProof = "bad_proof"
    case notMember = "not_member"
    case already
}

struct KioskCheckInResult: Hashable {
    var status: String
    var shortName: String?
    var belt: Belt?
    var creditsLeft: Int
    var hasSubscription: Bool

    var kind: KioskCheckInStatus { KioskCheckInStatus(rawValue: status) ?? .badProof }
}

struct KioskSettings: Hashable {
    var waiverText: String
    var hasPin: Bool
}

struct KioskAttendanceRow: Identifiable, Hashable {
    let id: UUID
    var isGuest: Bool
    var displayName: String
    var belt: Belt?
    var classStart: String?
    var unpaid: Bool
    var creditsLeft: Int?
    var createdAt: Date
}

struct KioskLeadDraft: Hashable {
    var name: String
    var email: String
    var phone: String
    var belt: Belt
}

struct KioskGuestDraft: Hashable {
    var name: String
    var phone: String
    var email: String
    var waiverAccepted: Bool
}
