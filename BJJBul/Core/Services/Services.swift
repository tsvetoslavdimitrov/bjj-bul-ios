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
    func acceptTerms(version: String) async throws
}

protocol AuthService {
    func currentUserId() async -> UUID?
    func signInWithApple(idToken: String, nonce: String) async throws
    func sendEmailCode(to email: String) async throws
    func verifyEmailCode(email: String, code: String) async throws
    func signOut() async throws
    func deleteAccount() async throws
}

protocol SocialService {
    /// Newest first. Pass the last post's `cursor` as `before` to load the next page.
    func feed(scope: FeedScope, authorId: UUID?, before: String?, limit: Int) async throws -> [Post]
    /// `images` are already-compressed JPEG data (max 4).
    func createPost(body: String, type: PostType, gymId: UUID?, images: [Data]) async throws
    func deletePost(id: UUID) async throws
    func setLike(postId: UUID, liked: Bool) async throws
    func comments(postId: UUID) async throws -> [PostComment]
    func addComment(postId: UUID, body: String) async throws
    func deleteComment(id: UUID) async throws
    func profile(userId: UUID) async throws -> PublicProfile?
    func setFollow(userId: UUID, following: Bool) async throws
    func report(_ target: ReportTarget, reason: ReportReason) async throws
    func block(userId: UUID) async throws
}
