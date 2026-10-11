import Foundation
import Supabase

struct SupabaseEventService: EventService {
    let client: SupabaseClient

    func upcomingEvents() async throws -> [CompetitionEvent] {
        let today = EventDates.string(from: Date())
        let rows: [EventRow] = try await client.from("events")
            .select("id,smoothcomp_id,name,starts_at,ends_at,city,venue,latitude,longitude,url,image_url,registration_url,registration_deadline,registration_info")
            .gte("ends_at", value: today)
            .order("starts_at")
            .limit(200)
            .execute()
            .value
        return rows.compactMap { $0.toModel() }
    }
}

struct EventRow: Decodable {
    let id: UUID
    let smoothcomp_id: Int
    let name: String
    let starts_at: String
    let ends_at: String?
    let city: String?
    let venue: String?
    let latitude: Double?
    let longitude: Double?
    let url: String
    let image_url: String?
    let registration_url: String?
    let registration_deadline: String?
    let registration_info: String?

    func toModel() -> CompetitionEvent? {
        guard let start = EventDates.date(from: starts_at), let link = URL(string: url) else { return nil }
        let end = ends_at.flatMap { EventDates.date(from: $0) } ?? start
        return CompetitionEvent(id: id, smoothcompId: smoothcomp_id, name: name, startsAt: start, endsAt: end,
                                city: city, venue: venue, latitude: latitude, longitude: longitude, url: link,
                                imageURL: image_url.flatMap { URL(string: $0) },
                                registrationURL: registration_url.flatMap { URL(string: $0) },
                                registrationDeadline: registration_deadline.flatMap { EventDates.date(from: $0) },
                                registrationInfo: registration_info)
    }
}
