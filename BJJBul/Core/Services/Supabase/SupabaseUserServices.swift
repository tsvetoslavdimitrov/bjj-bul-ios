import Foundation
import Supabase

struct SupabaseAuthService: AuthService {
    let client: SupabaseClient

    func currentUserId() async -> UUID? {
        do {
            let session = try await client.auth.session
            return session.user.id
        } catch {
            return nil
        }
    }

    func signInWithApple(idToken: String, nonce: String) async throws {
        _ = try await client.auth.signInWithIdToken(
            credentials: OpenIDConnectCredentials(provider: .apple, idToken: idToken, nonce: nonce)
        )
    }

    static let redirectURL = URL(string: "bjjbul://login")!

    /// Sends a one-time code (and magic link to bjjbul://login) to the email address.
    func sendEmailCode(to email: String) async throws {
        try await client.auth.signInWithOTP(email: email, redirectTo: Self.redirectURL)
    }

    /// Tries type .email first, then .magiclink (older templates / existing users).
    func verifyEmailCode(email: String, code: String) async throws {
        do {
            _ = try await client.auth.verifyOTP(email: email, token: code, type: .email)
        } catch {
            do {
                _ = try await client.auth.verifyOTP(email: email, token: code, type: .magiclink)
            } catch {
                throw error
            }
        }
    }

    func signUp(email: String, password: String) async throws -> Bool {
        let response = try await client.auth.signUp(email: email, password: password, redirectTo: Self.redirectURL)
        return response.session != nil
    }

    func signIn(email: String, password: String) async throws {
        _ = try await client.auth.signIn(email: email, password: password)
    }

    func sendPasswordReset(email: String) async throws {
        try await client.auth.resetPasswordForEmail(email, redirectTo: Self.redirectURL)
    }

    func updatePassword(_ password: String) async throws {
        _ = try await client.auth.update(user: UserAttributes(password: password))
    }

    func handleAuthURL(_ url: URL) async throws -> Bool {
        _ = try await client.auth.session(from: url)
        return url.absoluteString.contains("type=recovery")
    }

    func signOut() async throws {
        try await client.auth.signOut()
    }

    /// Calls the security-definer RPC from migration 0003, then clears the local session.
    func deleteAccount() async throws {
        try await client.rpc("delete_my_account").execute()
        try? await client.auth.signOut()
    }
}

struct SupabaseUserService: UserService {
    let client: SupabaseClient

    private func userId() async throws -> UUID {
        let session = try await client.auth.session
        return session.user.id
    }

    func currentUser() async throws -> AppUser? {
        let id = try await userId()
        let rows: [ProfileRow] = try await client.from("profiles")
            .select()
            .eq("id", value: id.uuidString)
            .limit(1)
            .execute()
            .value
        let favorites = try await favoriteGymIds()
        if let row = rows.first {
            return row.toModel(favoriteGymIds: favorites)
        }
        return AppUser(id: id, displayName: "", avatarURL: nil, belt: .white, stripes: 0,
                       homeGymId: nil, trainingSince: nil, locale: "bg",
                       favoriteGymIds: favorites, isPublic: false, smoothcompProfileURL: nil)
    }

    func update(_ user: AppUser) async throws {
        let payload = ProfileUpsert(id: user.id, displayName: user.displayName,
                                    belt: user.belt.rawValue, stripes: user.stripes,
                                    homeGymId: user.homeGymId)
        try await client.from("profiles")
            .upsert(payload)
            .execute()
        let athlete = AthleteProfileUpdate(
            team: user.team.flatMap { $0.isEmpty ? nil : $0 },
            teamGymId: user.teamGymId,
            smoothcompProfileURL: user.smoothcompProfileURL?.absoluteString)
        do {
            try await client.from("profiles")
                .update(athlete)
                .eq("id", value: user.id.uuidString)
                .execute()
        } catch {
            // Before migration 0009 the team columns don't exist; only fail if the user set them.
            let hasAthleteData = (athlete.team != nil) || (athlete.teamGymId != nil)
                || (athlete.smoothcompProfileURL != nil)
            if hasAthleteData { throw error }
        }
    }

    func favoriteGymIds() async throws -> [UUID] {
        let rows: [FavoriteRow] = try await client.from("favorite_gyms")
            .select("user_id,gym_id")
            .execute()
            .value
        return rows.map { $0.gym_id }
    }

    func setFavorite(gymId: UUID, isFavorite: Bool) async throws {
        let id = try await userId()
        if isFavorite {
            try await client.from("favorite_gyms")
                .upsert(FavoriteRow(user_id: id, gym_id: gymId), onConflict: "user_id,gym_id")
                .execute()
        } else {
            try await client.from("favorite_gyms")
                .delete()
                .eq("user_id", value: id.uuidString)
                .eq("gym_id", value: gymId.uuidString)
                .execute()
        }
    }

    func submitSuggestion(entityType: String, entityId: UUID?, message: String) async throws {
        let id = try await userId()
        let row = SuggestionInsert(user_id: id, entity_type: entityType, entity_id: entityId,
                                   payload: ["message": message])
        try await client.from("suggestions")
            .insert(row)
            .execute()
    }

    func acceptTerms(version: String) async throws {
        try await client.rpc("accept_terms", params: AcceptTermsParams(p_version: version))
            .execute()
    }
}

struct AcceptTermsParams: Encodable {
    let p_version: String
}
