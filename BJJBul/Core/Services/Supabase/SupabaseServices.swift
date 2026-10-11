import Foundation
import Supabase

struct SupabaseGymService: GymService {
    let client: SupabaseClient

    private let gymColumns = "id,name,name_latin,city_id,address,affiliation,phone,email,website,instagram,facebook,photo_urls,price_drop_in,price_monthly,price_kids,currency,has_kids,has_women_only,verified,owner_user_id"

    func cities() async throws -> [City] {
        let rows: [CityRow] = try await client.from("cities")
            .select("id,slug,name_bg,name_en,oblast")
            .order("name_bg")
            .execute()
            .value
        return rows.map { $0.toModel() }
    }

    func gyms(cityId: UUID?) async throws -> [Gym] {
        let rows = try await fetchGyms(cityId: cityId, id: nil)
        return rows.map { $0.toModel() }
    }

    /// Only gyms with real coordinates, for map pins.
    func mappableGyms() async throws -> [Gym] {
        let rows = try await fetchGyms(cityId: nil, id: nil)
        return rows.filter { $0.hasLocation }.map { $0.toModel() }
    }

    func gym(id: UUID) async throws -> Gym? {
        let rows = try await fetchGyms(cityId: nil, id: id)
        return rows.first?.toModel()
    }

    func schedule(gymId: UUID) async throws -> [ClassSchedule] {
        let rows: [ScheduleRow] = try await client.from("class_schedules")
            .select()
            .eq("gym_id", value: gymId.uuidString)
            .order("weekday")
            .order("start_time")
            .execute()
            .value
        return rows.map { $0.toModel() }
    }

    /// Reads the gyms_with_coords view (has lat/lng). If the view is unavailable
    /// (e.g. PGRST205), falls back to the plain gyms table without coordinates.
    private func fetchGyms(cityId: UUID?, id: UUID?) async throws -> [GymRow] {
        do {
            do {
                return try await query(table: "gyms_with_coords",
                                       columns: gymColumns + ",lat,lng,instagram_embed_url,rating_avg,rating_count",
                                       cityId: cityId, id: id)
            } catch {
                // View from before 0007 (no rating / embed columns).
                return try await query(table: "gyms_with_coords", columns: gymColumns + ",lat,lng", cityId: cityId, id: id)
            }
        } catch {
            return try await query(table: "gyms", columns: gymColumns, cityId: cityId, id: id)
        }
    }

    private func query(table: String, columns: String, cityId: UUID?, id: UUID?) async throws -> [GymRow] {
        var builder = client.from(table).select(columns)
        if let cityId {
            builder = builder.eq("city_id", value: cityId.uuidString)
        }
        if let id {
            builder = builder.eq("id", value: id.uuidString)
        }
        let rows: [GymRow] = try await builder
            .order("name")
            .execute()
            .value
        return rows
    }
}

struct SupabaseCoachService: CoachService {
    let client: SupabaseClient

    private let baseColumns = "id,full_name,full_name_latin,photo_url,belt,degree,promoted_by_coach_id,lineage_text,achievements,instagram,user_id,gym_coaches(gym_id)"

    func coaches() async throws -> [Coach] {
        let rows = try await fetchCoaches(id: nil)
        return rows.map { $0.toModel() }
    }

    func coaches(gymId: UUID) async throws -> [Coach] {
        let all = try await coaches()
        return all.filter { $0.gymIds.contains(gymId) }
    }

    func coach(id: UUID) async throws -> Coach? {
        let rows = try await fetchCoaches(id: id)
        return rows.first?.toModel()
    }

    /// Tries with the `bio` column (added in 0003); falls back if it doesn't exist yet.
    private func fetchCoaches(id: UUID?) async throws -> [CoachRow] {
        do {
            return try await query(columns: baseColumns + ",bio", id: id)
        } catch {
            return try await query(columns: baseColumns, id: id)
        }
    }

    private func query(columns: String, id: UUID?) async throws -> [CoachRow] {
        var builder = client.from("coaches").select(columns)
        if let id {
            builder = builder.eq("id", value: id.uuidString)
        }
        let rows: [CoachRow] = try await builder
            .order("full_name")
            .execute()
            .value
        return rows
    }
}
