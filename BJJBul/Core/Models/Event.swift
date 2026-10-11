import Foundation

struct CompetitionEvent: Identifiable, Hashable {
    let id: UUID
    let smoothcompId: Int
    var name: String
    /// All-day dates in Bulgarian local time.
    var startsAt: Date
    var endsAt: Date
    var city: String?
    var venue: String?
    var latitude: Double?
    var longitude: Double?
    var url: URL
    var imageURL: URL?
    var registrationURL: URL?
    var registrationDeadline: Date?
    var registrationInfo: String?

    var isMultiDay: Bool {
        !Calendar.bulgaria.isDate(startsAt, inSameDayAs: endsAt)
    }
}

extension Calendar {
    static var bulgaria: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Sofia") ?? .current
        return calendar
    }
}

enum EventDates {
    /// Parses "yyyy-MM-dd" as a date in Europe/Sofia.
    static func date(from string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.bulgaria
        formatter.timeZone = Calendar.bulgaria.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: String(string.prefix(10)))
    }

    static func string(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.bulgaria
        formatter.timeZone = Calendar.bulgaria.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    /// e.g. "октомври 2026" / "October 2026".
    static func monthTitle(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = Calendar.bulgaria.timeZone
        formatter.locale = Locale.current
        formatter.setLocalizedDateFormatFromTemplate("LLLL yyyy")
        return formatter.string(from: date).capitalized
    }

    static func dayText(_ event: CompetitionEvent) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = Calendar.bulgaria.timeZone
        formatter.locale = Locale.current
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        if event.isMultiDay {
            return "\(formatter.string(from: event.startsAt)) – \(formatter.string(from: event.endsAt))"
        }
        return formatter.string(from: event.startsAt)
    }
}
