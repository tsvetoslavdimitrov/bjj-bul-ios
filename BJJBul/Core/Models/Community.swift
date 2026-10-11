import Foundation

// MARK: - Reviews

struct GymReview: Identifiable, Hashable {
    let id: UUID
    let gymId: UUID
    let userId: UUID
    var authorName: String
    var rating: Int
    var body: String
    var createdAt: Date
}

// MARK: - Open mats

enum OpenMatStyle: String, CaseIterable, Hashable {
    case gi, nogi, both

    var localizedKey: String { "openmat.style.\(rawValue)" }
}

struct OpenMat: Identifiable, Hashable {
    let id: UUID
    let gymId: UUID
    var gymName: String
    var cityId: UUID?
    var startsAt: Date
    var endsAt: Date
    var style: OpenMatStyle
    var fee: Double?
    var currency: String
    var notes: String
    var verified: Bool
    var postedBy: UUID?
}

struct OpenMatDraft {
    var gymId: UUID
    var startsAt: Date
    var endsAt: Date
    var style: OpenMatStyle
    var fee: Double?
    var notes: String
}

// MARK: - Contributions

enum GymSubmissionKind: String {
    case newGym = "new_gym"
    case locationFix = "location_fix"
}

struct GymSubmissionDraft {
    var kind: GymSubmissionKind
    var gymId: UUID?
    var name: String
    var affiliation: String
    var phone: String
    var instagram: String
    var website: String
    var city: String
    var address: String
    var latitude: Double
    var longitude: Double
}

// MARK: - Drop-ins

struct DropInDraft {
    var gymId: UUID
    var preferredDate: Date?
    var preferredClass: String
    var message: String
}

enum DropInStatus: String, Hashable {
    case pending, contacted, closed

    var localizedKey: String { "dropin.status.\(rawValue)" }
}

struct DropInRequest: Identifiable, Hashable {
    let id: UUID
    let gymId: UUID
    var gymName: String
    var preferredDate: Date?
    var preferredClass: String?
    var message: String
    var status: DropInStatus
    var createdAt: Date
}

// MARK: - Training log

enum TrainingType: String, CaseIterable, Hashable {
    case gi, nogi, openmat, competition

    var localizedKey: String { "training.type.\(rawValue)" }
}

struct TrainingSession: Identifiable, Hashable {
    let id: UUID
    var date: Date
    var durationMinutes: Int
    var type: TrainingType
    var gymId: UUID?
    var techniques: [String]
    var sparringRounds: Int
    var notes: String
    /// 1...5, nil when not rated.
    var rating: Int?

    static func new() -> TrainingSession {
        TrainingSession(id: UUID(), date: Date(), durationMinutes: 90, type: .gi, gymId: nil,
                        techniques: [], sparringRounds: 0, notes: "", rating: nil)
    }
}

// MARK: - Notifications

struct AppNotification: Identifiable, Hashable {
    let id: UUID
    var kind: String
    var title: String
    var body: String
    var url: URL?
    var createdAt: Date
    var isRead: Bool
}

struct NotificationPreferences: Hashable {
    var newEvents: Bool = true
    var openMatsFollowed: Bool = true
}

// MARK: - Date helpers (DateFormatter only; avoids FormatStyle time-zone API differences)

enum BGDate {
    static let timeZone: TimeZone = TimeZone(identifier: "Europe/Sofia") ?? .current

    static func string(_ date: Date, date dateStyle: DateFormatter.Style, time timeStyle: DateFormatter.Style) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.timeZone = timeZone
        formatter.dateStyle = dateStyle
        formatter.timeStyle = timeStyle
        return formatter.string(from: date)
    }

    static func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.timeZone = timeZone
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    /// e.g. "събота, 24 октомври"
    static func dayTitle(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate("EEEEdMMMM")
        return formatter.string(from: date)
    }

    static func shortDay(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.timeZone = timeZone
        formatter.dateFormat = "d.MM"
        return formatter.string(from: date)
    }

    /// ISO 8601 with time zone, for timestamptz columns.
    static func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}
