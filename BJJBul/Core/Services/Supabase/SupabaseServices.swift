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
        let rows: [GymRow]
        if let cityId {
            rows = try await client.from("gyms")
                .select(gymColumns)
                .eq("city_id", value: cityId.uuidString)
                .order("name")
                .execute()
                .value
        } else {
            rows = try await client.from("gyms")
                .select(gymColumns)
                .order("name")
                .execute()
                .value
        }
        return rows.map { $0.toModel() }
    }

    func gym(id: UUID) async throws -> Gym? {
        let rows: [GymRow] = try await client.from("gyms")
            .select(gymColumns)
            .eq("id", value: id.uuidString)
            .limit(1)
            .execute()
            .value
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
}

struct SupabaseCoachService: CoachService {
    let client: SupabaseClient

    private let coachColumns = "id,full_name,full_name_latin,photo_url,belt,degree,promoted_by_coach_id,lineage_text,achievements,instagram,user_id,gym_coaches(gym_id)"

    func coaches() async throws -> [Coach] {
        let rows: [CoachRow] = try await client.from("coaches")
            .select(coachColumns)
            .order("full_name")
            .execute()
            .value
        return rows.map { $0.toModel() }
    }

    func coaches(gymId: UUID) async throws -> [Coach] {
        let all = try await coaches()
        return all.filter { $0.gymIds.contains(gymId) }
    }
}
