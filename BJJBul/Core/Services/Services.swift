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
    func coach(id: UUID) async throws -> Coach?
}

protocol UserService {
    /// Profile of the signed-in user, or nil when signed out.
    func currentUser() async throws -> AppUser?
    func update(_ user: AppUser) async throws
    func favoriteGymIds() async throws -> [UUID]
    func setFavorite(gymId: UUID, isFavorite: Bool) async throws
    func submitSuggestion(entityType: String, entityId: UUID?, message: String) async throws
}

protocol AuthService {
    func currentUserId() async -> UUID?
    func signInWithApple(idToken: String, nonce: String) async throws
    func sendEmailCode(to email: String) async throws
    func verifyEmailCode(email: String, code: String) async throws
    func signOut() async throws
    func deleteAccount() async throws
}
