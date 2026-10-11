import Foundation

enum AIChatRole: String, Hashable {
    case user, assistant
}

struct AIChatMessage: Identifiable, Hashable {
    let id: UUID
    var role: AIChatRole
    var text: String
    var createdAt: Date
}

struct AIChatReply: Hashable {
    var text: String
    var conversationId: UUID?
    var remaining: Int
    var limit: Int
}

struct AIUsage: Hashable {
    var remaining: Int
    var limit: Int
}

enum AIChatError: Error, LocalizedError {
    case dailyLimit
    case notConfigured
    case unauthorized
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .dailyLimit: return String(localized: "ai.error.limit")
        case .notConfigured: return String(localized: "ai.error.notConfigured")
        case .unauthorized: return String(localized: "ai.signIn")
        case .failed: return String(localized: "ai.error.failed")
        }
    }
}

enum AIStarterPrompts {
    static func prompts(bulgarian: Bool) -> [String] {
        if bulgarian {
            return [
                "Как да изляза от странично задържане?",
                "Обясни точките по правилата на IBJJF",
                "Кои зали има в Пловдив?",
                "Има ли предстоящи състезания?",
                "Дай ми план за тренировки за бял колан",
            ]
        }
        return [
            "How do I escape side control?",
            "Explain IBJJF scoring",
            "Which gyms are in Sofia?",
            "Any upcoming competitions?",
            "Give me a white belt training plan",
        ]
    }
}
