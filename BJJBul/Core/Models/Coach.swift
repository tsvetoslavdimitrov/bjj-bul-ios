import Foundation

struct Achievement: Codable, Hashable {
    var title: String
    var year: Int?
    var event: String?
}

enum CoachRole: String, Codable, Hashable {
    case head, instructor, assistant
}

struct Coach: Identifiable, Codable, Hashable {
    let id: UUID
    var fullName: String
    var fullNameLatin: String?
    var photoURL: URL?
    var belt: Belt
    var degree: Int
    var promotedByCoachId: UUID?
    var lineageText: String?
    var achievements: [Achievement]
    var instagram: String?
    var gymIds: [UUID]
    // Phase 2 hook: link to a user account
    var userId: UUID?
}
