import Foundation

struct AthleteRecord: Hashable {
    var wins: Int
    var losses: Int
    var winsSubmission: Int
    var winsPoints: Int
    var syncedAt: Date?

    /// Share of wins by submission, 0...100.
    var submissionPercent: Int {
        guard wins > 0 else { return 0 }
        return Int((Double(winsSubmission) / Double(wins) * 100).rounded())
    }
}

enum MedalSource: String, Hashable {
    case manual, smoothcomp
}

struct AthleteMedal: Identifiable, Hashable {
    let id: UUID
    var eventName: String
    /// 1 gold, 2 silver, 3 bronze
    var placement: Int
    var division: String?
    var eventDate: Date?
    var source: MedalSource
    var verified: Bool

    var localizedPlacementKey: String {
        switch placement {
        case 1: return "medal.gold"
        case 2: return "medal.silver"
        default: return "medal.bronze"
        }
    }
}

struct MedalDraft {
    var eventName: String
    var placement: Int
    var division: String
    var eventDate: Date?
}

struct MedalCounts: Hashable {
    var gold = 0
    var silver = 0
    var bronze = 0

    init(_ medals: [AthleteMedal]) {
        for medal in medals {
            switch medal.placement {
            case 1: gold += 1
            case 2: silver += 1
            default: bronze += 1
            }
        }
    }
}

/// Status values written by the smoothcomp-sync Edge Function.
enum SmoothcompSyncStatus: String {
    case ok, blocked, noData = "no_data", cached, invalidURL = "invalid_url", error

    var localizedKey: String { "smoothcomp.status.\(rawValue)" }
}
