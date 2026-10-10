import Foundation
import Observation

/// Dependency container plus session state. Falls back to mocks when Supabase isn't configured.
@Observable
final class AppServices {
    let gyms: GymService
    let coaches: CoachService
    let users: UserService
    let auth: AuthService

    var currentUser: AppUser?
    var favoriteGymIds: Set<UUID> = []

    var isSignedIn: Bool { currentUser != nil }

    init(gyms: GymService, coaches: CoachService, users: UserService, auth: AuthService) {
        self.gyms = gyms
        self.coaches = coaches
        self.users = users
        self.auth = auth
    }

    @MainActor
    func refreshSession() async {
        guard await auth.currentUserId() != nil else {
            currentUser = nil
            favoriteGymIds = []
            return
        }
        currentUser = try? await users.currentUser()
        let favorites = (try? await users.favoriteGymIds()) ?? []
        favoriteGymIds = Set(favorites)
    }

    static let live: AppServices = {
        guard let client = SupabaseConfig.makeClient() else { return mock }
        return AppServices(
            gyms: SupabaseGymService(client: client),
            coaches: SupabaseCoachService(client: client),
            users: SupabaseUserService(client: client),
            auth: SupabaseAuthService(client: client)
        )
    }()

    static let mock = AppServices(
        gyms: MockGymService(),
        coaches: MockCoachService(),
        users: MockUserService(),
        auth: MockAuthService()
    )
}
