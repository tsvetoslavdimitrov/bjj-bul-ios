import Foundation

enum ClaimStatus: String, Codable, Hashable {
    case none, pending, approved
}

struct Gym: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var nameLatin: String?
    var cityId: UUID
    var address: String
    var latitude: Double
    var longitude: Double
    var affiliation: String?
    var phone: String?
    var email: String?
    var website: URL?
    var instagram: String?
    var facebook: String?
    var photoURLs: [URL]
    var priceDropIn: Decimal?
    var priceMonthly: Decimal?
    var priceKids: Decimal?
    var currency: String
    var hasKids: Bool
    var hasWomenOnly: Bool
    var verified: Bool
    var lastVerifiedAt: Date?
    // Phase 2 hooks
    var ownerUserId: UUID?
    var claimStatus: ClaimStatus
    // Community (0007)
    var instagramEmbedURL: URL? = nil
    var ratingAverage: Double? = nil
    var ratingCount: Int = 0
}
