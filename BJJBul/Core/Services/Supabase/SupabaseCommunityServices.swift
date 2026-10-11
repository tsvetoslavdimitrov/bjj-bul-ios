import Foundation
import Supabase

private func currentUserId(_ client: SupabaseClient) async throws -> UUID {
    let session = try await client.auth.session
    return session.user.id
}

// MARK: - Reviews

struct SupabaseReviewService: ReviewService {
    let client: SupabaseClient

    func reviews(gymId: UUID) async throws -> [GymReview] {
        let rows: [ReviewRow] = try await client.rpc("get_gym_reviews", params: GymParam(p_gym: gymId))
            .execute()
            .value
        return rows.map { $0.toModel() }
    }

    func saveReview(gymId: UUID, rating: Int, body: String) async throws {
        let uid = try await currentUserId(client)
        let row = ReviewUpsert(gym_id: gymId, user_id: uid, rating: rating, body: body)
        try await client.from("gym_reviews")
            .upsert(row, onConflict: "gym_id,user_id")
            .execute()
    }

    func deleteReview(id: UUID) async throws {
        try await client.from("gym_reviews")
            .delete()
            .eq("id", value: id.uuidString)
            .execute()
    }
}

struct GymParam: Encodable {
    let p_gym: UUID
}

struct ReviewUpsert: Encodable {
    let gym_id: UUID
    let user_id: UUID
    let rating: Int
    let body: String
}

struct ReviewRow: Decodable {
    let id: UUID
    let gym_id: UUID
    let user_id: UUID
    let author_name: String?
    let rating: Int
    let body: String
    let created_at: String

    func toModel() -> GymReview {
        GymReview(id: id, gymId: gym_id, userId: user_id, authorName: author_name ?? "",
                  rating: rating, body: body, createdAt: DateParsing.date(from: created_at))
    }
}

// MARK: - Open mats

struct SupabaseOpenMatService: OpenMatService {
    let client: SupabaseClient

    func upcomingOpenMats() async throws -> [OpenMat] {
        let rows: [OpenMatRow] = try await client.from("open_mats")
            .select("id,gym_id,starts_at,ends_at,style,fee,currency,notes,verified,posted_by,gyms(name,city_id)")
            .gte("ends_at", value: BGDate.iso(Date()))
            .order("starts_at")
            .limit(300)
            .execute()
            .value
        return rows.map { $0.toModel() }
    }

    func createOpenMat(_ draft: OpenMatDraft) async throws {
        let uid = try await currentUserId(client)
        let row = OpenMatInsert(gym_id: draft.gymId, starts_at: BGDate.iso(draft.startsAt),
                                ends_at: BGDate.iso(draft.endsAt), style: draft.style.rawValue,
                                fee: draft.fee, notes: draft.notes, posted_by: uid)
        try await client.from("open_mats")
            .insert(row)
            .execute()
    }

    func deleteOpenMat(id: UUID) async throws {
        try await client.from("open_mats")
            .delete()
            .eq("id", value: id.uuidString)
            .execute()
    }
}

struct OpenMatInsert: Encodable {
    let gym_id: UUID
    let starts_at: String
    let ends_at: String
    let style: String
    let fee: Double?
    let notes: String
    let posted_by: UUID
}

struct GymNameRow: Decodable {
    let name: String?
    let city_id: UUID?
}

struct OpenMatRow: Decodable {
    let id: UUID
    let gym_id: UUID
    let starts_at: String
    let ends_at: String
    let style: String
    let fee: Double?
    let currency: String?
    let notes: String?
    let verified: Bool
    let posted_by: UUID?
    let gyms: GymNameRow?

    func toModel() -> OpenMat {
        OpenMat(id: id, gymId: gym_id, gymName: gyms?.name ?? "", cityId: gyms?.city_id,
                startsAt: DateParsing.date(from: starts_at), endsAt: DateParsing.date(from: ends_at),
                style: OpenMatStyle(rawValue: style) ?? .both, fee: fee, currency: currency ?? "EUR",
                notes: notes ?? "", verified: verified, postedBy: posted_by)
    }
}

// MARK: - Contributions, drop-ins, gym follows

struct SupabaseContributionService: ContributionService {
    let client: SupabaseClient

    func submitGym(_ draft: GymSubmissionDraft) async throws {
        let uid = try await currentUserId(client)
        let row = SubmissionInsert(kind: draft.kind.rawValue, gym_id: draft.gymId, submitted_by: uid,
                                   name: draft.name.isEmpty ? nil : draft.name,
                                   affiliation: draft.affiliation, phone: draft.phone,
                                   instagram: draft.instagram, website: draft.website,
                                   city_name: draft.city, address: draft.address,
                                   latitude: draft.latitude, longitude: draft.longitude)
        try await client.from("gym_submissions")
            .insert(row)
            .execute()
    }

    func submitDropIn(_ draft: DropInDraft) async throws {
        let uid = try await currentUserId(client)
        let row = DropInInsert(gym_id: draft.gymId, user_id: uid,
                               preferred_date: draft.preferredDate.map { EventDates.string(from: $0) },
                               preferred_class: draft.preferredClass.isEmpty ? nil : draft.preferredClass,
                               message: draft.message)
        try await client.from("drop_in_requests")
            .insert(row)
            .execute()
    }

    func myDropInRequests() async throws -> [DropInRequest] {
        let uid = try await currentUserId(client)
        let rows: [DropInRow] = try await client.from("drop_in_requests")
            .select("id,gym_id,preferred_date,preferred_class,message,status,created_at,gyms(name,city_id)")
            .eq("user_id", value: uid.uuidString)
            .order("created_at", ascending: false)
            .execute()
            .value
        return rows.map { $0.toModel() }
    }

    func isFollowingGym(_ gymId: UUID) async throws -> Bool {
        let uid = try await currentUserId(client)
        let rows: [GymFollowRow] = try await client.from("gym_follows")
            .select("user_id,gym_id")
            .eq("user_id", value: uid.uuidString)
            .eq("gym_id", value: gymId.uuidString)
            .execute()
            .value
        return !rows.isEmpty
    }

    func setFollowGym(_ gymId: UUID, following: Bool) async throws {
        let uid = try await currentUserId(client)
        if following {
            try await client.from("gym_follows")
                .upsert(GymFollowRow(user_id: uid, gym_id: gymId), onConflict: "user_id,gym_id")
                .execute()
        } else {
            try await client.from("gym_follows")
                .delete()
                .eq("user_id", value: uid.uuidString)
                .eq("gym_id", value: gymId.uuidString)
                .execute()
        }
    }
}

struct SubmissionInsert: Encodable {
    let kind: String
    let gym_id: UUID?
    let submitted_by: UUID
    let name: String?
    let affiliation: String
    let phone: String
    let instagram: String
    let website: String
    let city_name: String
    let address: String
    let latitude: Double
    let longitude: Double
}

struct DropInInsert: Encodable {
    let gym_id: UUID
    let user_id: UUID
    let preferred_date: String?
    let preferred_class: String?
    let message: String
}

struct GymFollowRow: Codable {
    let user_id: UUID
    let gym_id: UUID
}

struct DropInRow: Decodable {
    let id: UUID
    let gym_id: UUID
    let preferred_date: String?
    let preferred_class: String?
    let message: String
    let status: String
    let created_at: String
    let gyms: GymNameRow?

    func toModel() -> DropInRequest {
        DropInRequest(id: id, gymId: gym_id, gymName: gyms?.name ?? "",
                      preferredDate: preferred_date.flatMap { EventDates.date(from: $0) },
                      preferredClass: preferred_class, message: message,
                      status: DropInStatus(rawValue: status) ?? .pending,
                      createdAt: DateParsing.date(from: created_at))
    }
}

// MARK: - Training log

struct SupabaseTrainingService: TrainingService {
    let client: SupabaseClient

    func sessions() async throws -> [TrainingSession] {
        let rows: [TrainingRow] = try await client.from("training_sessions")
            .select("id,date,duration_minutes,type,gym_id,techniques,sparring_rounds,notes,rating")
            .order("date", ascending: false)
            .limit(1000)
            .execute()
            .value
        return rows.compactMap { $0.toModel() }
    }

    func save(_ session: TrainingSession) async throws {
        let uid = try await currentUserId(client)
        let row = TrainingUpsert(id: session.id, userId: uid, date: EventDates.string(from: session.date),
                                 durationMinutes: session.durationMinutes, type: session.type.rawValue,
                                 gymId: session.gymId, techniques: session.techniques,
                                 sparringRounds: session.sparringRounds, notes: session.notes,
                                 rating: session.rating)
        try await client.from("training_sessions")
            .upsert(row)
            .execute()
    }

    func delete(id: UUID) async throws {
        try await client.from("training_sessions")
            .delete()
            .eq("id", value: id.uuidString)
            .execute()
    }
}

/// Encodes optional fields explicitly as null so they can be cleared.
struct TrainingUpsert: Encodable {
    let id: UUID
    let userId: UUID
    let date: String
    let durationMinutes: Int
    let type: String
    let gymId: UUID?
    let techniques: [String]
    let sparringRounds: Int
    let notes: String
    let rating: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case date
        case durationMinutes = "duration_minutes"
        case type
        case gymId = "gym_id"
        case techniques
        case sparringRounds = "sparring_rounds"
        case notes
        case rating
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(userId, forKey: .userId)
        try container.encode(date, forKey: .date)
        try container.encode(durationMinutes, forKey: .durationMinutes)
        try container.encode(type, forKey: .type)
        try container.encode(gymId, forKey: .gymId)
        try container.encode(techniques, forKey: .techniques)
        try container.encode(sparringRounds, forKey: .sparringRounds)
        try container.encode(notes, forKey: .notes)
        try container.encode(rating, forKey: .rating)
    }
}

struct TrainingRow: Decodable {
    let id: UUID
    let date: String
    let duration_minutes: Int
    let type: String
    let gym_id: UUID?
    let techniques: [String]?
    let sparring_rounds: Int?
    let notes: String?
    let rating: Int?

    func toModel() -> TrainingSession? {
        guard let day = EventDates.date(from: date) else { return nil }
        return TrainingSession(id: id, date: day, durationMinutes: duration_minutes,
                               type: TrainingType(rawValue: type) ?? .gi, gymId: gym_id,
                               techniques: techniques ?? [], sparringRounds: sparring_rounds ?? 0,
                               notes: notes ?? "", rating: rating)
    }
}

// MARK: - Notifications

struct SupabaseNotificationService: NotificationService {
    let client: SupabaseClient

    func notifications() async throws -> [AppNotification] {
        let rows: [NotificationRow] = try await client.from("notifications")
            .select("id,kind,title,body,data,read_at,created_at")
            .order("created_at", ascending: false)
            .limit(100)
            .execute()
            .value
        return rows.map { $0.toModel() }
    }

    func markAllRead() async throws {
        let uid = try await currentUserId(client)
        try await client.from("notifications")
            .update(ReadUpdate(read_at: BGDate.iso(Date())))
            .eq("user_id", value: uid.uuidString)
            .execute()
    }

    func preferences() async throws -> NotificationPreferences {
        let rows: [PrefsRow] = try await client.from("notification_prefs")
            .select("user_id,new_events,open_mats_followed")
            .execute()
            .value
        guard let row = rows.first else { return NotificationPreferences() }
        return NotificationPreferences(newEvents: row.new_events, openMatsFollowed: row.open_mats_followed)
    }

    func savePreferences(_ preferences: NotificationPreferences) async throws {
        let uid = try await currentUserId(client)
        let row = PrefsRow(user_id: uid, new_events: preferences.newEvents,
                           open_mats_followed: preferences.openMatsFollowed)
        try await client.from("notification_prefs")
            .upsert(row, onConflict: "user_id")
            .execute()
    }

    func registerDevice(token: String, environment: String) async throws {
        try await client.rpc("register_device", params: DeviceParams(p_token: token, p_environment: environment))
            .execute()
    }
}

struct ReadUpdate: Encodable {
    let read_at: String
}

struct PrefsRow: Codable {
    let user_id: UUID
    let new_events: Bool
    let open_mats_followed: Bool
}

struct DeviceParams: Encodable {
    let p_token: String
    let p_environment: String
}

struct NotificationRow: Decodable {
    let id: UUID
    let kind: String
    let title: String
    let body: String
    let data: [String: String]?
    let read_at: String?
    let created_at: String

    func toModel() -> AppNotification {
        AppNotification(id: id, kind: kind, title: title, body: body,
                        url: data?["url"].flatMap { URL(string: $0) },
                        createdAt: DateParsing.date(from: created_at), isRead: read_at != nil)
    }
}

// MARK: - Quotes

struct SupabaseQuoteService: QuoteService {
    let client: SupabaseClient

    /// Falls back to the bundled list if the table is missing or empty.
    func quotes() async throws -> [Quote] {
        do {
            let rows: [QuoteRow] = try await client.from("quotes")
                .select("id,text_en,text_bg,author")
                .execute()
                .value
            let items = rows.map { Quote(id: $0.id, textEn: $0.text_en, textBg: $0.text_bg, author: $0.author) }
            return items.isEmpty ? MockQuoteData.quotes : items
        } catch {
            return MockQuoteData.quotes
        }
    }
}

struct QuoteRow: Decodable {
    let id: UUID
    let text_en: String
    let text_bg: String
    let author: String?
}

// MARK: - Ask BJJ (Edge Function "ask-bjj")

struct AskBJJRequest: Encodable {
    let message: String?
    let conversation_id: String?
    let locale: String?
    let action: String?
}

struct AskBJJResponse: Decodable {
    let reply: String?
    let conversation_id: String?
    let remaining: Int?
    let limit: Int?
}

struct SupabaseAIChatService: AIChatService {
    let client: SupabaseClient

    func send(message: String, conversationId: UUID?, locale: String) async throws -> AIChatReply {
        let body = AskBJJRequest(message: message, conversation_id: conversationId?.uuidString,
                                 locale: locale, action: nil)
        let response = try await invoke(body)
        return AIChatReply(text: response.reply ?? "",
                           conversationId: response.conversation_id.flatMap { UUID(uuidString: $0) },
                           remaining: response.remaining ?? 0,
                           limit: response.limit ?? 0)
    }

    func usage() async throws -> AIUsage {
        let response = try await invoke(AskBJJRequest(message: nil, conversation_id: nil, locale: nil, action: "usage"))
        return AIUsage(remaining: response.remaining ?? 0, limit: response.limit ?? 0)
    }

    private func invoke(_ body: AskBJJRequest) async throws -> AskBJJResponse {
        do {
            let response: AskBJJResponse = try await client.functions.invoke(
                "ask-bjj",
                options: FunctionInvokeOptions(body: body)
            )
            return response
        } catch let error as FunctionsError {
            if case .httpError(let code, _) = error {
                switch code {
                case 429: throw AIChatError.dailyLimit
                case 401: throw AIChatError.unauthorized
                case 503: throw AIChatError.notConfigured
                default: throw AIChatError.failed("HTTP \(code)")
                }
            }
            throw AIChatError.failed(error.localizedDescription)
        }
    }
}
