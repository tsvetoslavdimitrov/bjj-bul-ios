import Foundation

/// Mock data mirrors the real Bulgarian events seeded in migration 0006 (as listed on Smoothcomp on 2026-10-11).
struct MockEventService: EventService {
    func upcomingEvents() async throws -> [CompetitionEvent] {
        let items: [(Int, String, String, String, URL)] = [
            (33584, "ADCC Sofia Winter Open 2026", "2026-10-25", "Sofia", URL(string: "https://smoothcomp.com/en/event/33584")!),
            (33192, "FUJI European Open 2026", "2026-11-14", "Sofia", URL(string: "https://fujibjj.smoothcomp.com/en/event/33192")!),
            (34839, "TFR VI- Time for rolling VI", "2026-11-21", "Стара Загора", URL(string: "https://smoothcomp.com/en/event/34839")!),
            (32871, "Grappling Industries SOFIA", "2026-12-19", "Sofia", URL(string: "https://grapplingindustries.smoothcomp.com/en/event/32871")!)
        ]
        return items.compactMap { item in
            guard let date = EventDates.date(from: item.2) else { return nil }
            return CompetitionEvent(id: UUID(), smoothcompId: item.0, name: item.1, startsAt: date, endsAt: date,
                                    city: item.3, venue: nil, latitude: nil, longitude: nil, url: item.4,
                                    imageURL: nil, registrationURL: item.4, registrationDeadline: nil,
                                    registrationInfo: nil)
        }
    }
}
