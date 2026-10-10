import Foundation
import Observation

/// Simple dependency container. Swap mocks for Supabase-backed implementations later.
@Observable
final class AppServices {
    let gyms: GymService
    let coaches: CoachService
    let users: UserService

    init(gyms: GymService, coaches: CoachService, users: UserService) {
        self.gyms = gyms
        self.coaches = coaches
        self.users = users
    }

    static let mock = AppServices(
        gyms: MockGymService(),
        coaches: MockCoachService(),
        users: MockUserService()
    )
}
