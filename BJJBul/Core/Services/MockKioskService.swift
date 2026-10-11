import Foundation

final class MockKioskService: KioskService {
    private var rows: [KioskAttendanceRow] = []
    private var waiver = "I train at my own risk and confirm I'm fit to train."
    private let demo = KioskMember(userId: UUID(), shortName: "Ivan P.", belt: .blue, hasPin: true)

    func myMemberQR() async throws -> MemberQR {
        MemberQR(token: UUID().uuidString.lowercased(), expiresAt: Date().addingTimeInterval(120),
                 memberCode: "DEMO1234", hasPin: false)
    }
    func setMemberPin(_ pin: String) async throws {}
    func settings(gymId: UUID) async throws -> KioskSettings { KioskSettings(waiverText: waiver, hasPin: false) }
    func saveSettings(gymId: UUID, pin: String?, waiver: String?) async throws {
        if let waiver { self.waiver = waiver }
    }
    func verifyStaffPin(gymId: UUID, pin: String) async throws -> Bool { true }
    func searchMembers(gymId: UUID, query: String) async throws -> [KioskMember] {
        query.count >= 2 ? [demo] : []
    }
    func resolveQR(gymId: UUID, payload: String) async throws -> KioskMember? {
        payload.hasPrefix("bjjbul:") ? demo : nil
    }
    func checkIn(gymId: UUID, classId: UUID?, userId: UUID?, proof: String, allowUnpaid: Bool) async throws -> KioskCheckInResult {
        if proof == "0000" { return KioskCheckInResult(status: "bad_proof", shortName: nil, belt: nil, creditsLeft: 0, hasSubscription: false) }
        rows.insert(KioskAttendanceRow(id: UUID(), isGuest: false, displayName: demo.shortName, belt: demo.belt,
                                       classStart: nil, unpaid: allowUnpaid, creditsLeft: 4, createdAt: Date()), at: 0)
        return KioskCheckInResult(status: allowUnpaid ? "unpaid" : "ok", shortName: demo.shortName, belt: demo.belt,
                                  creditsLeft: 4, hasSubscription: false)
    }
    func recordPayment(gymId: UUID, userId: UUID, planId: UUID, method: MemberPaymentMethod, staffPin: String) async throws -> Int { 10 }
    func createLead(gymId: UUID, draft: KioskLeadDraft) async throws -> UUID { UUID() }
    func inviteLead(leadId: UUID) async throws -> UUID { demo.userId }
    func guestCheckIn(gymId: UUID, classId: UUID?, draft: KioskGuestDraft, planId: UUID?,
                      method: MemberPaymentMethod?, staffPin: String) async throws {
        rows.insert(KioskAttendanceRow(id: UUID(), isGuest: true, displayName: draft.name, belt: nil, classStart: nil,
                                       unpaid: method == nil, creditsLeft: nil, createdAt: Date()), at: 0)
    }
    func attendanceToday(gymId: UUID) async throws -> [KioskAttendanceRow] { rows }
}
