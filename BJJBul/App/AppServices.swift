import Foundation
import Observation

/// Dependency container plus session state. Falls back to mocks when Supabase isn't configured.
@Observable
final class AppServices {
    let gyms: GymService
    let coaches: CoachService
    let users: UserService
    let auth: AuthService
    let social: SocialService
    let events: EventService

    var currentUser: AppUser?
    var favoriteGymIds: Set<UUID> = []

    var isSignedIn: Bool { currentUser != nil }

    /// Signed in but hasn't accepted the current Terms of Use yet.
    var needsTermsAcceptance: Bool {
        guard let user = currentUser else { return false }
        return user.termsAcceptedAt == nil || user.termsVersion != AppConfig.termsVersion
    }

    init(gyms: GymService, coaches: CoachService, users: UserService, auth: AuthService,
         social: SocialService, events: EventService) {
        self.gyms = gyms
        self.coaches = coaches
        self.users = users
        self.auth = auth
        self.social = social
        self.events = events
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
            auth: SupabaseAuthService(client: client),
            social: SupabaseSocialService(client: client),
            events: SupabaseEventService(client: client)
        )
    }()

    static let mock = AppServices(
        gyms: MockGymService(),
        coaches: MockCoachService(),
        users: MockUserService(),
        auth: MockAuthService(),
        social: MockSocialService(),
        events: MockEventService()
    )
}
