import Foundation
import EventKit

enum CalendarAddResult {
    case added
    case denied
    case failed(String)
}

/// Adds an all-day event to the user's default calendar (write-only access on iOS 17+).
enum CalendarService {
    static func add(_ event: CompetitionEvent) async -> CalendarAddResult {
        let store = EKEventStore()
        do {
            let granted = try await store.requestWriteOnlyAccessToEvents()
            guard granted else { return .denied }
            let item = EKEvent(eventStore: store)
            item.title = event.name
            item.isAllDay = true
            item.startDate = event.startsAt
            item.endDate = event.endsAt
            item.timeZone = Calendar.bulgaria.timeZone
            item.location = [event.venue, event.city].compactMap { $0 }.joined(separator: ", ")
            item.url = event.url
            item.notes = event.url.absoluteString
            item.calendar = store.defaultCalendarForNewEvents
            try store.save(item, span: .thisEvent)
            return .added
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
