import Foundation

enum ClassType: String, Codable, CaseIterable, Hashable {
    case gi, nogi, kids, fundamentals, competition, openmat, women
}

enum ClassLevel: String, Codable, Hashable {
    case all, beginner, advanced
}

struct ClassSchedule: Identifiable, Codable, Hashable {
    let id: UUID
    var gymId: UUID
    var coachId: UUID?
    /// 1 = Monday ... 7 = Sunday
    var weekday: Int
    /// "HH:mm", 24h
    var startTime: String
    var endTime: String
    var type: ClassType
    var level: ClassLevel
    var notes: String?
}
