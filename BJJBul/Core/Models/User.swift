import Foundation

struct AppUser: Identifiable, Codable, Hashable {
    let id: UUID
    var displayName: String
    var avatarURL: URL?
    var belt: Belt
    var stripes: Int
    var homeGymId: UUID?
    var trainingSince: Date?
    var locale: String
    var favoriteGymIds: [UUID]
    // Phase 2/3 hooks
    var isPublic: Bool
    var smoothcompProfileURL: URL?
}
