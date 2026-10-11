import Foundation

final class MockAthleteService: AthleteService {
    private var stored: [AthleteMedal] = [
        AthleteMedal(id: UUID(), eventName: "Bulgarian Open (demo)", placement: 1, division: "Adult / Blue / -76 kg",
                     eventDate: nil, source: .manual, verified: false),
    ]

    func record(userId: UUID) async throws -> AthleteRecord? {
        AthleteRecord(wins: 7, losses: 3, winsSubmission: 4, winsPoints: 3, syncedAt: nil)
    }
    func medals(userId: UUID) async throws -> [AthleteMedal] { stored }
    func addMedal(_ draft: MedalDraft) async throws {
        stored.insert(AthleteMedal(id: UUID(), eventName: draft.eventName, placement: draft.placement,
                                   division: draft.division.isEmpty ? nil : draft.division,
                                   eventDate: draft.eventDate, source: .manual, verified: false), at: 0)
    }
    func deleteMedal(id: UUID) async throws { stored.removeAll { $0.id == id } }
    func syncSmoothcomp() async throws -> String { SmoothcompSyncStatus.blocked.rawValue }
}

final class MockGymManagementService: GymManagementService {
    private let gymId = MockData.gyms.first?.id ?? UUID()
    private var members: [RosterMember] = []
    private var plansList: [Membership] = []
    private var checkIns: Set<String> = []
    private var paidUsers: Set<UUID> = []

    init() {
        members = [
            RosterMember(memberId: UUID(), userId: MockData.user.id, displayName: MockData.user.displayName,
                         avatarURL: nil, belt: .purple, stripes: 1, role: .owner, status: .active, membershipId: nil),
            RosterMember(memberId: UUID(), userId: UUID(), displayName: "Иван", avatarURL: nil,
                         belt: .white, stripes: 2, role: .student, status: .active, membershipId: nil),
            RosterMember(memberId: UUID(), userId: UUID(), displayName: "Мария", avatarURL: nil,
                         belt: .blue, stripes: 0, role: .student, status: .pending, membershipId: nil),
        ]
        plansList = [Membership(id: UUID(), gymId: gymId, name: "Monthly", price: 60, currency: "EUR",
                                period: .monthly, active: true)]
    }

    func myGyms() async throws -> [MyGym] {
        let name = MockData.gyms.first?.name ?? "Demo gym"
        return [MyGym(gymId: gymId, name: name, slug: "demo", role: .owner, status: .active, hasAccess: true)]
    }
    func claimGym(_ draft: GymClaimDraft) async throws {}
    func requestMembership(gymId: UUID) async throws {}
    func redeemInvite(code: String) async throws -> UUID { gymId }
    func createInvite(gymId: UUID, role: GymRole, maxUses: Int) async throws -> String { "DEMO1234" }

    func roster(gymId: UUID) async throws -> [RosterMember] { members.filter { $0.status != .removed } }
    func setMemberStatus(memberId: UUID, status: MemberStatus) async throws {
        if let index = members.firstIndex(where: { $0.memberId == memberId }) { members[index].status = status }
    }
    func setMemberMembership(memberId: UUID, membershipId: UUID?) async throws {
        if let index = members.firstIndex(where: { $0.memberId == memberId }) { members[index].membershipId = membershipId }
    }
    func setMemberRole(memberId: UUID, role: GymRole) async throws {
        if let index = members.firstIndex(where: { $0.memberId == memberId }) { members[index].role = role }
    }
    func promote(gymId: UUID, userId: UUID, belt: Belt, stripes: Int, note: String, postToFeed: Bool) async throws {
        if let index = members.firstIndex(where: { $0.userId == userId }) {
            members[index].belt = belt
            members[index].stripes = stripes
        }
    }

    func saveClass(_ item: ClassSchedule, isNew: Bool) async throws {}
    func deleteClass(id: UUID) async throws {}
    private func key(_ classId: UUID, _ userId: UUID, _ date: Date) -> String {
        "\(classId)-\(userId)-\(BGDate.shortDay(date))"
    }
    func attendance(gymId: UUID, classId: UUID, date: Date) async throws -> Set<UUID> {
        Set(members.map { $0.userId }.filter { checkIns.contains(key(classId, $0, date)) })
    }
    func checkIn(gymId: UUID, classId: UUID, userId: UUID, date: Date) async throws {
        checkIns.insert(key(classId, userId, date))
    }
    func undoCheckIn(gymId: UUID, classId: UUID, userId: UUID, date: Date) async throws {
        checkIns.remove(key(classId, userId, date))
    }

    func memberships(gymId: UUID) async throws -> [Membership] { plansList }
    func saveMembership(_ membership: Membership, isNew: Bool) async throws {
        if let index = plansList.firstIndex(where: { $0.id == membership.id }) {
            plansList[index] = membership
        } else {
            plansList.append(membership)
        }
    }
    func deleteMembership(id: UUID) async throws { plansList.removeAll { $0.id == id } }
    func paymentStatus(gymId: UUID) async throws -> [PaymentStatusRow] {
        members.filter { $0.role == .student && $0.status == .active }.map { member in
            PaymentStatusRow(userId: member.userId, displayName: member.displayName, membershipName: "Monthly",
                             price: 60, paid: paidUsers.contains(member.userId),
                             paidAmount: paidUsers.contains(member.userId) ? 60 : 0, lastPaidAt: nil)
        }
    }
    func recordPayment(_ draft: MemberPaymentDraft) async throws { paidUsers.insert(draft.userId) }

    func subscription(gymId: UUID) async throws -> GymSubscription? {
        GymSubscription(status: .trialing, planId: nil, trialEndsAt: Date().addingTimeInterval(20 * 86400),
                        currentPeriodEnd: nil, method: nil)
    }
    func plans() async throws -> [BJJBulPlan] {
        [BJJBulPlan(id: UUID(), code: "basic", name: "Basic", priceMonthlyEUR: 19, features: []),
         BJJBulPlan(id: UUID(), code: "pro", name: "Pro", priceMonthlyEUR: 39, features: [])]
    }
    func updateGymProfile(_ draft: GymProfileDraft) async throws {}
    func uploadGymPhoto(gymId: UUID, jpegData: Data) async throws -> URL {
        URL(string: "https://example.com/demo.jpg")!
    }
}
