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

    func coach(id: UUID) async throws -> Coach? {
        MockData.coaches.first { $0.id == id }
    }
}

final class MockAuthService: AuthService {
    private var signedIn = false

    func currentUserId() async -> UUID? { signedIn ? MockData.user.id : nil }
    func signInWithApple(idToken: String, nonce: String) async throws { signedIn = true }
    func sendEmailCode(to email: String) async throws {}
    func verifyEmailCode(email: String, code: String) async throws { signedIn = true }
    func signOut() async throws { signedIn = false }
    func deleteAccount() async throws { signedIn = false }
}

final class MockUserService: UserService {
    private var user: AppUser = MockData.user
    private var favorites: Set<UUID> = Set(MockData.user.favoriteGymIds)

    func currentUser() async throws -> AppUser? { user }

    func update(_ user: AppUser) async throws { self.user = user }

    func favoriteGymIds() async throws -> [UUID] { Array(favorites) }

    func setFavorite(gymId: UUID, isFavorite: Bool) async throws {
        if isFavorite {
            favorites.insert(gymId)
        } else {
            favorites.remove(gymId)
        }
    }

    func submitSuggestion(entityType: String, entityId: UUID?, message: String) async throws {}

    func acceptTerms(version: String) async throws {
        user.termsAcceptedAt = Date()
        user.termsVersion = version
    }
}
