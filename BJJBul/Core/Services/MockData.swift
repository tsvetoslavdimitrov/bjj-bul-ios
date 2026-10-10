import Foundation

/// Sample data for previews and development. Not verified real-world data.
enum MockData {
    static let sofiaId = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    static let plovdivId = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    static let varnaId = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!

    static let cities: [City] = [
        City(id: sofiaId, nameBg: "София", nameEn: "Sofia", oblast: "София-град",
             latitude: 42.6977, longitude: 23.3219, slug: "sofia"),
        City(id: plovdivId, nameBg: "Пловдив", nameEn: "Plovdiv", oblast: "Пловдив",
             latitude: 42.1354, longitude: 24.7453, slug: "plovdiv"),
        City(id: varnaId, nameBg: "Варна", nameEn: "Varna", oblast: "Варна",
             latitude: 43.2141, longitude: 27.9147, slug: "varna")
    ]

    static let gym1Id = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
    static let gym2Id = UUID(uuidString: "00000000-0000-0000-0000-000000000102")!
    static let gym3Id = UUID(uuidString: "00000000-0000-0000-0000-000000000103")!

    static func makeGym(id: UUID, name: String, latin: String, cityId: UUID,
                        address: String, lat: Double, lng: Double,
                        monthly: Decimal) -> Gym {
        Gym(id: id, name: name, nameLatin: latin, cityId: cityId, address: address,
            latitude: lat, longitude: lng, affiliation: nil, phone: "+359 88 000 0000",
            email: nil, website: nil, instagram: nil, facebook: nil, photoURLs: [],
            priceDropIn: 15, priceMonthly: monthly, priceKids: 50, currency: "EUR",
            hasKids: true, hasWomenOnly: false, verified: false, lastVerifiedAt: nil,
            ownerUserId: nil, claimStatus: .none)
    }

    static let gyms: [Gym] = [
        makeGym(id: gym1Id, name: "Жиу-жицу Академия София", latin: "Jiu-Jitsu Academy Sofia",
                cityId: sofiaId, address: "бул. Витоша 1, София",
                lat: 42.6950, lng: 23.3210, monthly: 80),
        makeGym(id: gym2Id, name: "Граплинг Клуб Пловдив", latin: "Grappling Club Plovdiv",
                cityId: plovdivId, address: "ул. Главна 10, Пловдив",
                lat: 42.1420, lng: 24.7490, monthly: 60),
        makeGym(id: gym3Id, name: "BJJ Варна", latin: "BJJ Varna",
                cityId: varnaId, address: "бул. Приморски 5, Варна",
                lat: 43.2050, lng: 27.9200, monthly: 65)
    ]

    static let coach1Id = UUID(uuidString: "00000000-0000-0000-0000-000000000201")!
    static let coach2Id = UUID(uuidString: "00000000-0000-0000-0000-000000000202")!

    static let coaches: [Coach] = [
        Coach(id: coach1Id, fullName: "Иван Петров", fullNameLatin: "Ivan Petrov", photoURL: nil,
              belt: .black, degree: 2, promotedByCoachId: nil, lineageText: "Sample lineage",
              achievements: [Achievement(title: "Sample champion", year: 2024, event: "Sample Open")],
              instagram: nil, gymIds: [gym1Id], userId: nil),
        Coach(id: coach2Id, fullName: "Мария Георгиева", fullNameLatin: "Maria Georgieva", photoURL: nil,
              belt: .brown, degree: 1, promotedByCoachId: coach1Id, lineageText: nil,
              achievements: [], instagram: nil, gymIds: [gym2Id, gym3Id], userId: nil)
    ]

    static let schedules: [ClassSchedule] = [
        ClassSchedule(id: UUID(), gymId: gym1Id, coachId: coach1Id, weekday: 1,
                      startTime: "19:00", endTime: "20:30", type: .gi, level: .all, notes: nil),
        ClassSchedule(id: UUID(), gymId: gym1Id, coachId: coach1Id, weekday: 3,
                      startTime: "19:00", endTime: "20:30", type: .nogi, level: .all, notes: nil),
        ClassSchedule(id: UUID(), gymId: gym2Id, coachId: coach2Id, weekday: 2,
                      startTime: "18:30", endTime: "20:00", type: .fundamentals, level: .beginner, notes: nil)
    ]

    static let user = AppUser(id: UUID(), displayName: "Demo", avatarURL: nil, belt: .blue,
                              stripes: 2, homeGymId: gym1Id, trainingSince: nil, locale: "bg",
                              favoriteGymIds: [gym1Id], isPublic: false, smoothcompProfileURL: nil)
}
