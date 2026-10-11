import Foundation
import Supabase

struct SupabaseKioskService: KioskService {
    let client: SupabaseClient

    private struct QRRow: Decodable {
        let token: String
        let expires_at: String
        let member_code: String
        let has_pin: Bool
    }
    private struct PinParam: Encodable { let p_pin: String }
    private struct GymParam: Encodable { let p_gym: UUID }
    private struct SettingsRow: Decodable {
        let waiver_text: String?
        let has_pin: Bool?
    }
    private struct SettingsParams: Encodable {
        let p_gym: UUID
        let p_pin: String?
        let p_waiver: String?

        enum CodingKeys: String, CodingKey { case p_gym, p_pin, p_waiver }
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(p_gym, forKey: .p_gym)
            try c.encode(p_pin, forKey: .p_pin)
            try c.encode(p_waiver, forKey: .p_waiver)
        }
    }
    private struct GymPinParams: Encodable {
        let p_gym: UUID
        let p_pin: String
    }
    private struct SearchParams: Encodable {
        let p_gym: UUID
        let p_query: String
    }
    private struct MemberRow: Decodable {
        let user_id: UUID
        let short_name: String?
        let belt: String?
        let has_pin: Bool?
    }
    private struct ResolveParams: Encodable {
        let p_gym: UUID
        let p_payload: String
    }
    private struct ResolveRow: Decodable {
        let user_id: UUID
        let short_name: String?
        let belt: String?
        let member_status: String?
    }
    private struct CheckInParams: Encodable {
        let p_gym: UUID
        let p_class: UUID?
        let p_user: UUID?
        let p_proof: String
        let p_allow_unpaid: Bool

        enum CodingKeys: String, CodingKey { case p_gym, p_class, p_user, p_proof, p_allow_unpaid }
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(p_gym, forKey: .p_gym)
            try c.encode(p_class, forKey: .p_class)
            try c.encode(p_user, forKey: .p_user)
            try c.encode(p_proof, forKey: .p_proof)
            try c.encode(p_allow_unpaid, forKey: .p_allow_unpaid)
        }
    }
    private struct CheckInRow: Decodable {
        let status: String
        let short_name: String?
        let belt: String?
        let credits_left: Int?
        let has_subscription: Bool?
    }
    private struct PaymentParams: Encodable {
        let p_gym: UUID
        let p_user: UUID
        let p_membership: UUID
        let p_method: String
        let p_staff_pin: String
    }
    private struct LeadParams: Encodable {
        let p_gym: UUID
        let p_name: String
        let p_email: String
        let p_phone: String
        let p_belt: String
    }
    private struct InviteBody: Encodable { let lead_id: String }
    private struct InviteResponse: Decodable {
        let user_id: UUID?
        let error: String?
    }
    private struct GuestParams: Encodable {
        let p_gym: UUID
        let p_class: UUID?
        let p_name: String
        let p_phone: String
        let p_email: String
        let p_waiver_accepted: Bool
        let p_membership: UUID?
        let p_method: String?
        let p_staff_pin: String

        enum CodingKeys: String, CodingKey {
            case p_gym, p_class, p_name, p_phone, p_email, p_waiver_accepted, p_membership, p_method, p_staff_pin
        }
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(p_gym, forKey: .p_gym)
            try c.encode(p_class, forKey: .p_class)
            try c.encode(p_name, forKey: .p_name)
            try c.encode(p_phone, forKey: .p_phone)
            try c.encode(p_email, forKey: .p_email)
            try c.encode(p_waiver_accepted, forKey: .p_waiver_accepted)
            try c.encode(p_membership, forKey: .p_membership)
            try c.encode(p_method, forKey: .p_method)
            try c.encode(p_staff_pin, forKey: .p_staff_pin)
        }
    }
    private struct AttendanceRow: Decodable {
        let id: UUID
        let kind: String
        let display_name: String?
        let belt: String?
        let class_start: String?
        let unpaid: Bool?
        let credits_left: Int?
        let created_at: String
    }

    func myMemberQR() async throws -> MemberQR {
        let rows: [QRRow] = try await client.rpc("my_member_qr").execute().value
        guard let row = rows.first else { throw URLError(.badServerResponse) }
        return MemberQR(token: row.token, expiresAt: DateParsing.date(from: row.expires_at),
                        memberCode: row.member_code, hasPin: row.has_pin)
    }

    func setMemberPin(_ pin: String) async throws {
        try await client.rpc("set_member_pin", params: PinParam(p_pin: pin)).execute()
    }

    func settings(gymId: UUID) async throws -> KioskSettings {
        let rows: [SettingsRow] = try await client.rpc("get_kiosk_settings", params: GymParam(p_gym: gymId)).execute().value
        let row = rows.first
        return KioskSettings(waiverText: row?.waiver_text ?? "", hasPin: row?.has_pin ?? false)
    }

    func saveSettings(gymId: UUID, pin: String?, waiver: String?) async throws {
        try await client.rpc("set_kiosk_settings", params: SettingsParams(p_gym: gymId, p_pin: pin, p_waiver: waiver)).execute()
    }

    func verifyStaffPin(gymId: UUID, pin: String) async throws -> Bool {
        let ok: Bool = try await client.rpc("verify_kiosk_pin", params: GymPinParams(p_gym: gymId, p_pin: pin)).execute().value
        return ok
    }

    func searchMembers(gymId: UUID, query: String) async throws -> [KioskMember] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else { return [] }
        let rows: [MemberRow] = try await client.rpc("kiosk_search_members",
                                                     params: SearchParams(p_gym: gymId, p_query: trimmed))
            .execute().value
        return rows.map { KioskMember(userId: $0.user_id, shortName: $0.short_name ?? "—",
                                      belt: $0.belt.flatMap { Belt(rawValue: $0) }, hasPin: $0.has_pin ?? false) }
    }

    func resolveQR(gymId: UUID, payload: String) async throws -> KioskMember? {
        let rows: [ResolveRow] = try await client.rpc("kiosk_resolve_qr",
                                                      params: ResolveParams(p_gym: gymId, p_payload: payload))
            .execute().value
        guard let row = rows.first else { return nil }
        return KioskMember(userId: row.user_id, shortName: row.short_name ?? "—",
                           belt: row.belt.flatMap { Belt(rawValue: $0) }, hasPin: false)
    }

    func checkIn(gymId: UUID, classId: UUID?, userId: UUID?, proof: String, allowUnpaid: Bool) async throws -> KioskCheckInResult {
        let params = CheckInParams(p_gym: gymId, p_class: classId, p_user: userId, p_proof: proof, p_allow_unpaid: allowUnpaid)
        let rows: [CheckInRow] = try await client.rpc("kiosk_check_in", params: params).execute().value
        guard let row = rows.first else { throw URLError(.badServerResponse) }
        return KioskCheckInResult(status: row.status, shortName: row.short_name,
                                  belt: row.belt.flatMap { Belt(rawValue: $0) }, creditsLeft: row.credits_left ?? 0,
                                  hasSubscription: row.has_subscription ?? false)
    }

    func recordPayment(gymId: UUID, userId: UUID, planId: UUID, method: MemberPaymentMethod, staffPin: String) async throws -> Int {
        let params = PaymentParams(p_gym: gymId, p_user: userId, p_membership: planId, p_method: method.rawValue,
                                   p_staff_pin: staffPin)
        let credits: Int = try await client.rpc("kiosk_record_payment", params: params).execute().value
        return credits
    }

    func createLead(gymId: UUID, draft: KioskLeadDraft) async throws -> UUID {
        let params = LeadParams(p_gym: gymId, p_name: draft.name, p_email: draft.email, p_phone: draft.phone,
                                p_belt: draft.belt.rawValue)
        let id: UUID = try await client.rpc("kiosk_create_lead", params: params).execute().value
        return id
    }

    func inviteLead(leadId: UUID) async throws -> UUID {
        let response: InviteResponse = try await client.functions.invoke(
            "kiosk-invite",
            options: FunctionInvokeOptions(body: InviteBody(lead_id: leadId.uuidString.lowercased()))
        )
        guard let id = response.user_id else { throw KioskError.message(response.error ?? "invite failed") }
        return id
    }

    func guestCheckIn(gymId: UUID, classId: UUID?, draft: KioskGuestDraft, planId: UUID?,
                      method: MemberPaymentMethod?, staffPin: String) async throws {
        let params = GuestParams(p_gym: gymId, p_class: classId, p_name: draft.name, p_phone: draft.phone,
                                 p_email: draft.email, p_waiver_accepted: draft.waiverAccepted, p_membership: planId,
                                 p_method: method?.rawValue, p_staff_pin: staffPin)
        try await client.rpc("kiosk_guest_check_in", params: params).execute()
    }

    func attendanceToday(gymId: UUID) async throws -> [KioskAttendanceRow] {
        let rows: [AttendanceRow] = try await client.rpc("kiosk_attendance_today", params: GymParam(p_gym: gymId))
            .execute().value
        return rows.map { row in
            KioskAttendanceRow(id: row.id, isGuest: row.kind == "guest", displayName: row.display_name ?? "—",
                               belt: row.belt.flatMap { Belt(rawValue: $0) }, classStart: row.class_start,
                               unpaid: row.unpaid ?? false, creditsLeft: row.credits_left,
                               createdAt: DateParsing.date(from: row.created_at))
        }
    }
}

enum KioskError: Error, LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let text): return text
        }
    }
}
