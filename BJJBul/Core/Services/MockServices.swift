import Foundation

struct MockGymService: GymService {
    func cities() async throws -> [City] { MockData.cities }

    func gyms(cityId: UUID?) async throws -> [Gym] {
        guard let cityId else { return MockData.gyms }
        return MockData.gyms.filter { $0.cityId == cityId }
    }

    func gym(id: UUID) async throws -> Gym? {
        MockData.gyms.first { $0.id == id }
    }

    func schedule(gymId: UUID) async throws -> [ClassSchedule] {
        MockData.schedules.filter { $0.gymId == gymId }
    }
}

struct MockCoachService: CoachService {
    func coaches() async throws -> [Coach] { MockData.coaches }

    func coaches(gymId: UUID) async throws -> [Coach] {
        MockData.coaches.filter { $0.gymIds.contains(gymId) }
    }
}

final class MockUserService: UserService {
    private var user: AppUser? = MockData.user

    func currentUser() async throws -> AppUser? { user }

    func update(_ user: AppUser) async throws { self.user = user }
}
