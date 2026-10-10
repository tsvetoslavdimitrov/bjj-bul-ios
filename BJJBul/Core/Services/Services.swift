import Foundation

protocol GymService {
    func cities() async throws -> [City]
    func gyms(cityId: UUID?) async throws -> [Gym]
    func gym(id: UUID) async throws -> Gym?
    func schedule(gymId: UUID) async throws -> [ClassSchedule]
}

protocol CoachService {
    func coaches() async throws -> [Coach]
    func coaches(gymId: UUID) async throws -> [Coach]
}

protocol UserService {
    func currentUser() async throws -> AppUser?
    func update(_ user: AppUser) async throws
}
