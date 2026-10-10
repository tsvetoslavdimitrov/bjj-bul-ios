import Foundation

/// Row shapes returned by PostgREST (snake_case). Location is not selected directly;
/// lat/lng come from the gyms_near RPC or can be added via a view later.
struct CityRow: Decodable {
    let id: UUID
    let slug: String
    let name_bg: String
    let name_en: String
    let oblast: String?

    func toModel() -> City {
        City(id: id, nameBg: name_bg, nameEn: name_en, oblast: oblast ?? "",
             latitude: 0, longitude: 0, slug: slug)
    }
}

struct GymRow: Decodable {
    let id: UUID
    let name: String
    let name_latin: String?
    let city_id: UUID
    let address: String?
    let affiliation: String?
    let phone: String?
    let email: String?
    let website: String?
    let instagram: String?
    let facebook: String?
    let photo_urls: [String]?
    let price_drop_in: Decimal?
    let price_monthly: Decimal?
    let price_kids: Decimal?
    let currency: String?
    let has_kids: Bool?
    let has_women_only: Bool?
    let verified: Bool
    let owner_user_id: UUID?

    func toModel(latitude: Double = 0, longitude: Double = 0) -> Gym {
        Gym(id: id, name: name, nameLatin: name_latin, cityId: city_id,
            address: address ?? "", latitude: latitude, longitude: longitude,
            affiliation: affiliation, phone: phone, email: email,
            website: website.flatMap { URL(string: $0) },
            instagram: instagram, facebook: facebook,
            photoURLs: (photo_urls ?? []).compactMap { URL(string: $0) },
            priceDropIn: price_drop_in, priceMonthly: price_monthly, priceKids: price_kids,
            currency: currency ?? "EUR", hasKids: has_kids ?? false,
            hasWomenOnly: has_women_only ?? false, verified: verified,
            lastVerifiedAt: nil, ownerUserId: owner_user_id, claimStatus: .none)
    }
}

struct ScheduleRow: Decodable {
    let id: UUID
    let gym_id: UUID
    let coach_id: UUID?
    let weekday: Int
    let start_time: String
    let end_time: String
    let type: String
    let level: String
    let notes: String?

    func toModel() -> ClassSchedule {
        ClassSchedule(id: id, gymId: gym_id, coachId: coach_id, weekday: weekday,
                      startTime: String(start_time.prefix(5)), endTime: String(end_time.prefix(5)),
                      type: ClassType(rawValue: type) ?? .gi,
                      level: ClassLevel(rawValue: level) ?? .all, notes: notes)
    }
}

struct GymCoachLink: Decodable {
    let gym_id: UUID
}

struct CoachRow: Decodable {
    let id: UUID
    let full_name: String
    let full_name_latin: String?
    let photo_url: String?
    let belt: String?
    let degree: Int?
    let promoted_by_coach_id: UUID?
    let lineage_text: String?
    let achievements: [Achievement]?
    let instagram: String?
    let user_id: UUID?
    let gym_coaches: [GymCoachLink]?

    func toModel() -> Coach {
        Coach(id: id, fullName: full_name, fullNameLatin: full_name_latin,
              photoURL: photo_url.flatMap { URL(string: $0) },
              belt: belt.flatMap { Belt(rawValue: $0) } ?? .white, degree: degree ?? 0,
              promotedByCoachId: promoted_by_coach_id, lineageText: lineage_text,
              achievements: achievements ?? [], instagram: instagram,
              gymIds: (gym_coaches ?? []).map { $0.gym_id }, userId: user_id)
    }
}
