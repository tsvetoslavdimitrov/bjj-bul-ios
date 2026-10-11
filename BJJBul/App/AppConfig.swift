import Foundation

enum AppConfig {
    /// Support / moderation contact shown in the app and legal texts.
    static let contactEmail = "admin@bjjbul.com"
    /// Bump when Terms change significantly; users are asked to accept again.
    static let termsVersion = "1.0"

    /// BJJ Bul billing (gym subscriptions, paid outside the app; B2B billing instructions only).
    static let revolutMeURL = "https://revolut.me/tavetoopk"
    static let billingEmail = "admin@bjjbul.com"

    static var contactURL: URL? { URL(string: "mailto:\(contactEmail)") }
}
