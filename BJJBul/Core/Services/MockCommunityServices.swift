import Foundation

final class MockReviewService: ReviewService {
    private var items: [GymReview] = []

    func reviews(gymId: UUID) async throws -> [GymReview] {
        items.filter { $0.gymId == gymId }
    }

    func saveReview(gymId: UUID, rating: Int, body: String) async throws {
        items.removeAll { $0.gymId == gymId && $0.userId == MockData.user.id }
        items.insert(GymReview(id: UUID(), gymId: gymId, userId: MockData.user.id,
                               authorName: MockData.user.displayName, rating: rating, body: body,
                               createdAt: Date()), at: 0)
    }

    func deleteReview(id: UUID) async throws {
        items.removeAll { $0.id == id }
    }
}

final class MockOpenMatService: OpenMatService {
    private var items: [OpenMat]

    init() {
        let start = Date().addingTimeInterval(2 * 24 * 3600)
        items = [
            OpenMat(id: UUID(), gymId: MockData.gym1Id, gymName: MockData.gyms[0].name,
                    cityId: MockData.sofiaId, startsAt: start, endsAt: start.addingTimeInterval(7200),
                    style: .both, fee: nil, currency: "EUR", notes: "Sample open mat",
                    verified: false, postedBy: nil)
        ]
    }

    func upcomingOpenMats() async throws -> [OpenMat] { items }

    func createOpenMat(_ draft: OpenMatDraft) async throws {
        let gym = MockData.gyms.first { $0.id == draft.gymId }
        items.append(OpenMat(id: UUID(), gymId: draft.gymId, gymName: gym?.name ?? "",
                             cityId: gym?.cityId, startsAt: draft.startsAt, endsAt: draft.endsAt,
                             style: draft.style, fee: draft.fee, currency: "EUR", notes: draft.notes,
                             verified: false, postedBy: MockData.user.id))
        items.sort { $0.startsAt < $1.startsAt }
    }

    func deleteOpenMat(id: UUID) async throws {
        items.removeAll { $0.id == id }
    }
}

final class MockContributionService: ContributionService {
    private var requests: [DropInRequest] = []
    private var followed: Set<UUID> = []

    func submitGym(_ draft: GymSubmissionDraft) async throws {}

    func submitDropIn(_ draft: DropInDraft) async throws {
        let gym = MockData.gyms.first { $0.id == draft.gymId }
        requests.insert(DropInRequest(id: UUID(), gymId: draft.gymId, gymName: gym?.name ?? "",
                                      preferredDate: draft.preferredDate,
                                      preferredClass: draft.preferredClass, message: draft.message,
                                      status: .pending, createdAt: Date()), at: 0)
    }

    func myDropInRequests() async throws -> [DropInRequest] { requests }

    func isFollowingGym(_ gymId: UUID) async throws -> Bool { followed.contains(gymId) }

    func setFollowGym(_ gymId: UUID, following: Bool) async throws {
        if following {
            followed.insert(gymId)
        } else {
            followed.remove(gymId)
        }
    }
}

final class MockTrainingService: TrainingService {
    private var items: [TrainingSession] = []

    func sessions() async throws -> [TrainingSession] {
        items.sorted { $0.date > $1.date }
    }

    func save(_ session: TrainingSession) async throws {
        if let index = items.firstIndex(where: { $0.id == session.id }) {
            items[index] = session
        } else {
            items.append(session)
        }
    }

    func delete(id: UUID) async throws {
        items.removeAll { $0.id == id }
    }
}

final class MockNotificationService: NotificationService {
    private var items: [AppNotification] = [
        AppNotification(id: UUID(), kind: "new_event", title: "New competition: ADCC Sofia Winter Open 2026",
                        body: "Sofia · 25.10.2026", url: URL(string: "https://smoothcomp.com/en/event/33584"),
                        createdAt: Date(), isRead: false)
    ]
    private var prefs = NotificationPreferences()

    func notifications() async throws -> [AppNotification] { items }

    func markAllRead() async throws {
        for index in items.indices {
            items[index].isRead = true
        }
    }

    func preferences() async throws -> NotificationPreferences { prefs }

    func savePreferences(_ preferences: NotificationPreferences) async throws { prefs = preferences }

    func registerDevice(token: String, environment: String) async throws {}
}

struct MockQuoteService: QuoteService {
    func quotes() async throws -> [Quote] { MockQuoteData.quotes }
}
