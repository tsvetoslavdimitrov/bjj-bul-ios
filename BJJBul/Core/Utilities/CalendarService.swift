import Foundation
import EventKit

enum CalendarAddResult {
    case added
    case denied
    case failed(String)
}

/// Adds events to the user's default calendar (write-only access on iOS 17+).
enum CalendarService {
    static func add(_ event: CompetitionEvent) async -> CalendarAddResult {
        await add(title: event.name, start: event.startsAt, end: event.endsAt, allDay: true,
                  location: [event.venue, event.city].compactMap { $0 }.joined(separator: ", "),
                  url: event.url)
    }

    static func add(_ openMat: OpenMat) async -> CalendarAddResult {
        await add(title: "Open mat · \(openMat.gymName)", start: openMat.startsAt, end: openMat.endsAt,
                  allDay: false, location: openMat.gymName, url: nil)
    }

    static func add(title: String, start: Date, end: Date, allDay: Bool,
                    location: String, url: URL?) async -> CalendarAddResult {
        let store = EKEventStore()
        do {
            let granted = try await store.requestWriteOnlyAccessToEvents()
            guard granted else { return .denied }
            let item = EKEvent(eventStore: store)
            item.title = title
            item.isAllDay = allDay
            item.startDate = start
            item.endDate = end
            item.timeZone = Calendar.bulgaria.timeZone
            item.location = location
            item.url = url
            item.notes = url?.absoluteString
            item.calendar = store.defaultCalendarForNewEvents
            try store.save(item, span: .thisEvent)
            return .added
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
