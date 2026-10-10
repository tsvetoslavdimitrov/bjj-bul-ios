import Foundation

enum Belt: String, Codable, CaseIterable, Hashable {
    case white, blue, purple, brown, black, coral, red

    var localizedKey: String { "belt.\(rawValue)" }
}
