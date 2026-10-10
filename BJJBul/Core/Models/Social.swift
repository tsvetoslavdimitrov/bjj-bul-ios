import Foundation

enum PostType: String, Codable, CaseIterable, Hashable {
    case progress, promotion, competition, training

    var localizedKey: String { "post.type.\(rawValue)" }
}

enum FeedScope: String, CaseIterable, Hashable {
    case following, all

    var localizedKey: String { "feed.scope.\(rawValue)" }
}

struct Post: Identifiable, Hashable {
    let id: UUID
    let authorId: UUID
    var authorName: String
    var authorAvatarURL: URL?
    var authorBelt: Belt?
    var body: String
    var type: PostType
    var gymId: UUID?
    var gymName: String?
    var createdAt: Date
    /// Raw timestamp from the server, used as the pagination cursor (keeps full precision).
    var cursor: String
    var mediaURLs: [URL]
    var likeCount: Int
    var commentCount: Int
    var likedByMe: Bool
}

struct PostComment: Identifiable, Hashable {
    let id: UUID
    let postId: UUID
    let authorId: UUID
    var authorName: String
    var authorAvatarURL: URL?
    var body: String
    var createdAt: Date
}

struct PublicProfile: Identifiable, Hashable {
    let id: UUID
    var displayName: String
    var avatarURL: URL?
    var belt: Belt
    var stripes: Int
    var homeGymId: UUID?
    var followerCount: Int
    var followingCount: Int
    var postCount: Int
    var followedByMe: Bool
    var blocked: Bool
}

/// Navigation value for a user's public profile.
struct UserRoute: Hashable {
    let id: UUID
}

enum ReportReason: String, CaseIterable, Hashable {
    case spam, harassment, inappropriate, other

    var localizedKey: String { "report.reason.\(rawValue)" }
}

struct ReportTarget: Identifiable {
    let id = UUID()
    var postId: UUID?
    var commentId: UUID?
    var userId: UUID?
}

enum DateParsing {
    /// Parses Postgres timestamptz JSON (e.g. 2026-10-11T00:31:00.123456+00:00).
    /// Fractional seconds are dropped before parsing for robustness.
    static func date(from string: String) -> Date {
        var trimmed = string
        if let dot = trimmed.firstIndex(of: ".") {
            let rest = trimmed[dot...]
            if let zoneStart = rest.firstIndex(where: { $0 == "+" || $0 == "-" || $0 == "Z" }) {
                trimmed = String(trimmed[..<dot]) + String(trimmed[zoneStart...])
            } else {
                trimmed = String(trimmed[..<dot])
            }
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: trimmed) ?? Date()
    }
}
