import Foundation
import Supabase

private func signedInUserId(_ client: SupabaseClient) async throws -> UUID {
    let session = try await client.auth.session
    return session.user.id
}

private func decimalToDouble(_ value: Decimal?) -> Double? {
    guard let value else { return nil }
    return NSDecimalNumber(decimal: value).doubleValue
}

// MARK: - Athlete record & medals

struct AthleteRecordRow: Decodable {
    let wins: Int
    let losses: Int
    let wins_submission: Int
    let wins_points: Int
    let synced_at: String?
}

struct AthleteMedalRow: Decodable {
    let id: UUID
    let event_name: String
    let placement: Int
    let division: String?
    let event_date: String?
    let source: String
    let verified: Bool
}

struct MedalInsert: Encodable {
    let user_id: UUID
    let event_name: String
    let placement: Int
    let division: String?
    let event_date: String?
}

struct SmoothcompSyncResponse: Decodable {
    let status: String?
}

struct SupabaseAthleteService: AthleteService {
    let client: SupabaseClient

    func record(userId: UUID) async throws -> AthleteRecord? {
        let rows: [AthleteRecordRow] = try await client.from("athlete_records")
            .select("wins,losses,wins_submission,wins_points,synced_at")
            .eq("user_id", value: userId.uuidString)
            .limit(1)
            .execute()
            .value
        guard let row = rows.first else { return nil }
        return AthleteRecord(wins: row.wins, losses: row.losses, winsSubmission: row.wins_submission,
                             winsPoints: row.wins_points,
                             syncedAt: row.synced_at.map { DateParsing.date(from: $0) })
    }

    func medals(userId: UUID) async throws -> [AthleteMedal] {
        let rows: [AthleteMedalRow] = try await client.from("athlete_medals")
            .select("id,event_name,placement,division,event_date,source,verified")
            .eq("user_id", value: userId.uuidString)
            .order("event_date", ascending: false)
            .limit(200)
            .execute()
            .value
        return rows.map { row in
            AthleteMedal(id: row.id, eventName: row.event_name, placement: row.placement,
                         division: row.division, eventDate: row.event_date.flatMap { EventDates.date(from: $0) },
                         source: MedalSource(rawValue: row.source) ?? .manual, verified: row.verified)
        }
    }

    func addMedal(_ draft: MedalDraft) async throws {
        let uid = try await signedInUserId(client)
        let row = MedalInsert(user_id: uid, event_name: draft.eventName, placement: draft.placement,
                              division: draft.division.isEmpty ? nil : draft.division,
                              event_date: draft.eventDate.map { EventDates.string(from: $0) })
        try await client.from("athlete_medals").insert(row).execute()
    }

    func deleteMedal(id: UUID) async throws {
        try await client.from("athlete_medals").delete().eq("id", value: id.uuidString).execute()
    }

    func syncSmoothcomp() async throws -> String {
        do {
            let response: SmoothcompSyncResponse = try await client.functions.invoke("smoothcomp-sync")
            return response.status ?? SmoothcompSyncStatus.error.rawValue
        } catch let error as FunctionsError {
            if case .httpError(let code, _) = error, code == 400 {
                return SmoothcompSyncStatus.invalidURL.rawValue
            }
            throw error
        }
    }
}

// MARK: - Gym management

struct GymIdParam: Encodable { let p_gym: UUID }
struct MyGymRow: Decodable {
    let gym_id: UUID
    let gym_name: String
    let gym_slug: String
    let role: String
    let status: String
    let has_access: Bool
}
struct RosterRow: Decodable {
    let member_id: UUID
    let user_id: UUID
    let display_name: String?
    let avatar_url: String?
    let belt: String?
    let stripes: Int?
    let role: String
    let status: String
    let membership_id: UUID?
}
struct ClaimInsert: Encodable {
    let gym_id: UUID
    let user_id: UUID
    let role: String
    let message: String
    let contact: String?
}
struct InviteParams: Encodable {
    let p_gym: UUID
    let p_role: String
    let p_max_uses: Int
}
struct CodeParam: Encodable { let p_code: String }
struct MemberStatusUpdate: Encodable { let status: String }
struct MemberRoleUpdate: Encodable { let role: String }
struct MemberMembershipUpdate: Encodable {
    let membership_id: UUID?

    enum CodingKeys: String, CodingKey { case membership_id }
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(membership_id, forKey: .membership_id)
    }
}
struct PromoteParams: Encodable {
    let p_gym: UUID
    let p_user: UUID
    let p_belt: String
    let p_stripes: Int
    let p_note: String
    let p_post: Bool
}
struct ClassUpsert: Encodable {
    let id: UUID
    let gym_id: UUID
    let weekday: Int
    let start_time: String
    let end_time: String
    let type: String
    let level: String
    let notes: String?

    enum CodingKeys: String, CodingKey { case id, gym_id, weekday, start_time, end_time, type, level, notes }
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(gym_id, forKey: .gym_id)
        try container.encode(weekday, forKey: .weekday)
        try container.encode(start_time, forKey: .start_time)
        try container.encode(end_time, forKey: .end_time)
        try container.encode(type, forKey: .type)
        try container.encode(level, forKey: .level)
        try container.encode(notes, forKey: .notes)
    }
}
struct AttendanceRow: Decodable { let user_id: UUID }
struct AttendanceInsert: Encodable {
    let gym_id: UUID
    let class_schedule_id: UUID
    let user_id: UUID
    let class_date: String
}
struct MembershipRow: Decodable {
    let id: UUID
    let gym_id: UUID
    let name: String
    let price: Double
    let currency: String
    let period: String
    let active: Bool
}
struct MembershipUpsert: Encodable {
    let id: UUID
    let gym_id: UUID
    let name: String
    let price: Double
    let currency: String
    let period: String
    let active: Bool
}
struct PaymentStatusDTO: Decodable {
    let user_id: UUID
    let display_name: String?
    let membership_name: String?
    let price: Double?
    let paid: Bool
    let paid_amount: Double?
    let last_paid_at: String?
}
struct MemberPaymentInsert: Encodable {
    let gym_id: UUID
    let user_id: UUID
    let membership_id: UUID?
    let amount: Double
    let method: String
    let recorded_by: UUID
    let note: String?
}
struct SubscriptionRow: Decodable {
    let status: String
    let plan_id: UUID?
    let trial_ends_at: String?
    let current_period_end: String?
    let method: String?
}
struct PlanRow: Decodable {
    let id: UUID
    let code: String
    let name: String
    let price_monthly_eur: Double
    let features: [String]?
}
struct GymProfileParams: Encodable {
    let draft: GymProfileDraft

    enum CodingKeys: String, CodingKey {
        case p_gym, p_name, p_address, p_phone, p_email, p_website, p_instagram, p_facebook, p_affiliation
        case p_price_drop_in, p_price_monthly, p_price_kids, p_has_kids, p_has_women_only, p_photo_urls
    }

    // Every parameter is sent (nulls included) so PostgREST resolves the function signature.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(draft.gymId, forKey: .p_gym)
        try c.encode(draft.name, forKey: .p_name)
        try c.encode(draft.address, forKey: .p_address)
        try c.encode(draft.phone, forKey: .p_phone)
        try c.encode(draft.email, forKey: .p_email)
        try c.encode(draft.website, forKey: .p_website)
        try c.encode(draft.instagram, forKey: .p_instagram)
        try c.encode(draft.facebook, forKey: .p_facebook)
        try c.encode(draft.affiliation, forKey: .p_affiliation)
        try c.encode(decimalToDouble(draft.priceDropIn), forKey: .p_price_drop_in)
        try c.encode(decimalToDouble(draft.priceMonthly), forKey: .p_price_monthly)
        try c.encode(decimalToDouble(draft.priceKids), forKey: .p_price_kids)
        try c.encode(draft.hasKids, forKey: .p_has_kids)
        try c.encode(draft.hasWomenOnly, forKey: .p_has_women_only)
        try c.encode(draft.photoURLs.map { $0.absoluteString }, forKey: .p_photo_urls)
    }
}

struct SupabaseGymManagementService: GymManagementService {
    let client: SupabaseClient
    private let photoBucket = "gym-media"

    func myGyms() async throws -> [MyGym] {
        let rows: [MyGymRow] = try await client.rpc("my_gyms").execute().value
        return rows.map { row in
            MyGym(gymId: row.gym_id, name: row.gym_name, slug: row.gym_slug,
                  role: GymRole(rawValue: row.role) ?? .student,
                  status: MemberStatus(rawValue: row.status) ?? .pending, hasAccess: row.has_access)
        }
    }

    func claimGym(_ draft: GymClaimDraft) async throws {
        let uid = try await signedInUserId(client)
        let row = ClaimInsert(gym_id: draft.gymId, user_id: uid, role: draft.role.rawValue,
                              message: draft.message, contact: draft.contact.isEmpty ? nil : draft.contact)
        try await client.from("gym_claims").insert(row).execute()
    }

    func requestMembership(gymId: UUID) async throws {
        try await client.rpc("request_gym_membership", params: GymIdParam(p_gym: gymId)).execute()
    }

    func redeemInvite(code: String) async throws -> UUID {
        let id: UUID = try await client.rpc("redeem_gym_invite", params: CodeParam(p_code: code)).execute().value
        return id
    }

    func createInvite(gymId: UUID, role: GymRole, maxUses: Int) async throws -> String {
        let code: String = try await client.rpc("create_gym_invite",
                                                params: InviteParams(p_gym: gymId, p_role: role.rawValue,
                                                                     p_max_uses: maxUses))
            .execute()
            .value
        return code
    }

    func roster(gymId: UUID) async throws -> [RosterMember] {
        let rows: [RosterRow] = try await client.rpc("get_gym_roster", params: GymIdParam(p_gym: gymId))
            .execute()
            .value
        return rows.map { row in
            RosterMember(memberId: row.member_id, userId: row.user_id, displayName: row.display_name ?? "",
                         avatarURL: row.avatar_url.flatMap { URL(string: $0) },
                         belt: row.belt.flatMap { Belt(rawValue: $0) } ?? .white, stripes: row.stripes ?? 0,
                         role: GymRole(rawValue: row.role) ?? .student,
                         status: MemberStatus(rawValue: row.status) ?? .pending, membershipId: row.membership_id)
        }
    }

    func setMemberStatus(memberId: UUID, status: MemberStatus) async throws {
        try await client.from("gym_members").update(MemberStatusUpdate(status: status.rawValue))
            .eq("id", value: memberId.uuidString).execute()
    }

    func setMemberMembership(memberId: UUID, membershipId: UUID?) async throws {
        try await client.from("gym_members").update(MemberMembershipUpdate(membership_id: membershipId))
            .eq("id", value: memberId.uuidString).execute()
    }

    func setMemberRole(memberId: UUID, role: GymRole) async throws {
        try await client.from("gym_members").update(MemberRoleUpdate(role: role.rawValue))
            .eq("id", value: memberId.uuidString).execute()
    }

    func promote(gymId: UUID, userId: UUID, belt: Belt, stripes: Int, note: String, postToFeed: Bool) async throws {
        let params = PromoteParams(p_gym: gymId, p_user: userId, p_belt: belt.rawValue, p_stripes: stripes,
                                   p_note: note, p_post: postToFeed)
        try await client.rpc("promote_member", params: params).execute()
    }

    func saveClass(_ item: ClassSchedule, isNew: Bool) async throws {
        let row = ClassUpsert(id: item.id, gym_id: item.gymId, weekday: item.weekday,
                              start_time: item.startTime, end_time: item.endTime,
                              type: item.type.rawValue, level: item.level.rawValue,
                              notes: (item.notes ?? "").isEmpty ? nil : item.notes)
        if isNew {
            try await client.from("class_schedules").insert(row).execute()
        } else {
            try await client.from("class_schedules").update(row).eq("id", value: item.id.uuidString).execute()
        }
    }

    func deleteClass(id: UUID) async throws {
        try await client.from("class_schedules").delete().eq("id", value: id.uuidString).execute()
    }

    func attendance(gymId: UUID, classId: UUID, date: Date) async throws -> Set<UUID> {
        let rows: [AttendanceRow] = try await client.from("attendance")
            .select("user_id")
            .eq("class_schedule_id", value: classId.uuidString)
            .eq("class_date", value: EventDates.string(from: date))
            .execute()
            .value
        return Set(rows.map { $0.user_id })
    }

    func checkIn(gymId: UUID, classId: UUID, userId: UUID, date: Date) async throws {
        let row = AttendanceInsert(gym_id: gymId, class_schedule_id: classId, user_id: userId,
                                   class_date: EventDates.string(from: date))
        try await client.from("attendance").insert(row).execute()
    }

    func undoCheckIn(gymId: UUID, classId: UUID, userId: UUID, date: Date) async throws {
        try await client.from("attendance").delete()
            .eq("class_schedule_id", value: classId.uuidString)
            .eq("user_id", value: userId.uuidString)
            .eq("class_date", value: EventDates.string(from: date))
            .execute()
    }

    func memberships(gymId: UUID) async throws -> [Membership] {
        let rows: [MembershipRow] = try await client.from("memberships")
            .select("id,gym_id,name,price,currency,period,active")
            .eq("gym_id", value: gymId.uuidString)
            .order("price")
            .execute()
            .value
        return rows.map { row in
            Membership(id: row.id, gymId: row.gym_id, name: row.name, price: row.price, currency: row.currency,
                       period: MembershipPeriod(rawValue: row.period) ?? .monthly, active: row.active)
        }
    }

    func saveMembership(_ membership: Membership, isNew: Bool) async throws {
        let row = MembershipUpsert(id: membership.id, gym_id: membership.gymId, name: membership.name,
                                   price: membership.price, currency: membership.currency,
                                   period: membership.period.rawValue, active: membership.active)
        if isNew {
            try await client.from("memberships").insert(row).execute()
        } else {
            try await client.from("memberships").update(row).eq("id", value: membership.id.uuidString).execute()
        }
    }

    func deleteMembership(id: UUID) async throws {
        try await client.from("memberships").delete().eq("id", value: id.uuidString).execute()
    }

    func paymentStatus(gymId: UUID) async throws -> [PaymentStatusRow] {
        let rows: [PaymentStatusDTO] = try await client.rpc("gym_payment_status", params: GymIdParam(p_gym: gymId))
            .execute()
            .value
        return rows.map { row in
            PaymentStatusRow(userId: row.user_id, displayName: row.display_name ?? "",
                             membershipName: row.membership_name, price: row.price, paid: row.paid,
                             paidAmount: row.paid_amount ?? 0,
                             lastPaidAt: row.last_paid_at.map { DateParsing.date(from: $0) })
        }
    }

    func recordPayment(_ draft: MemberPaymentDraft) async throws {
        let uid = try await signedInUserId(client)
        let row = MemberPaymentInsert(gym_id: draft.gymId, user_id: draft.userId, membership_id: draft.membershipId,
                                      amount: draft.amount, method: draft.method.rawValue, recorded_by: uid,
                                      note: draft.note.isEmpty ? nil : draft.note)
        try await client.from("member_payments").insert(row).execute()
    }

    func subscription(gymId: UUID) async throws -> GymSubscription? {
        let rows: [SubscriptionRow] = try await client.from("gym_subscriptions")
            .select("status,plan_id,trial_ends_at,current_period_end,method")
            .eq("gym_id", value: gymId.uuidString)
            .limit(1)
            .execute()
            .value
        guard let row = rows.first else { return nil }
        return GymSubscription(status: SubscriptionStatus(rawValue: row.status) ?? .pastDue, planId: row.plan_id,
                               trialEndsAt: row.trial_ends_at.map { DateParsing.date(from: $0) },
                               currentPeriodEnd: row.current_period_end.map { DateParsing.date(from: $0) },
                               method: row.method)
    }

    func plans() async throws -> [BJJBulPlan] {
        let rows: [PlanRow] = try await client.from("plans")
            .select("id,code,name,price_monthly_eur,features")
            .order("sort")
            .execute()
            .value
        return rows.map { BJJBulPlan(id: $0.id, code: $0.code, name: $0.name,
                                     priceMonthlyEUR: $0.price_monthly_eur, features: $0.features ?? []) }
    }

    func updateGymProfile(_ draft: GymProfileDraft) async throws {
        try await client.rpc("update_gym_profile", params: GymProfileParams(draft: draft)).execute()
    }

    func uploadGymPhoto(gymId: UUID, jpegData: Data) async throws -> URL {
        let path = "\(gymId.uuidString.lowercased())/\(UUID().uuidString.lowercased()).jpg"
        _ = try await client.storage.from(photoBucket)
            .upload(path, data: jpegData, options: FileOptions(contentType: "image/jpeg"))
        return try client.storage.from(photoBucket).getPublicURL(path: path)
    }

    // MARK: Student payments (0011)

    func myStudentMemberships() async throws -> [StudentMembership] {
        let rows: [StudentMembershipRow] = try await client.rpc("my_student_memberships").execute().value
        return rows.map { row in
            StudentMembership(gymId: row.gym_id, gymName: row.gym_name, gymSlug: row.gym_slug,
                              revolutURL: row.revolut_url.flatMap { URL(string: $0) },
                              membershipId: row.membership_id, membershipName: row.membership_name,
                              price: row.price, currency: row.currency ?? "EUR",
                              period: row.period.flatMap { MembershipPeriod(rawValue: $0) } ?? .monthly,
                              paidUntil: row.paid_until.flatMap { EventDates.date(from: $0) },
                              nextDue: row.next_due.flatMap { EventDates.date(from: $0) },
                              status: PaymentPeriodStatus(rawValue: row.status) ?? .due,
                              pendingClaims: row.pending_claims ?? 0)
        }
    }

    func myPayments(gymId: UUID) async throws -> [PaymentRecord] {
        let uid = try await signedInUserId(client)
        let rows: [PaymentRecordRow] = try await client.from("member_payments")
            .select("id,amount,currency,method,paid_at,period_month")
            .eq("gym_id", value: gymId.uuidString)
            .eq("user_id", value: uid.uuidString)
            .order("paid_at", ascending: false)
            .limit(100)
            .execute()
            .value
        return rows.map { row in
            PaymentRecord(id: row.id, amount: row.amount, currency: row.currency ?? "EUR",
                          method: MemberPaymentMethod(rawValue: row.method) ?? .cash,
                          paidAt: DateParsing.date(from: row.paid_at),
                          periodMonth: row.period_month.flatMap { EventDates.date(from: $0) })
        }
    }

    func submitPaymentClaim(_ draft: PaymentClaimDraft) async throws {
        let uid = try await signedInUserId(client)
        let row = PaymentClaimInsert(gym_id: draft.gymId, user_id: uid, membership_id: draft.membershipId,
                                     period_month: String(EventDates.string(from: draft.periodMonth).prefix(7)) + "-01",
                                     amount: draft.amount, method: draft.method.rawValue,
                                     reference: draft.reference, note: draft.note.isEmpty ? nil : draft.note)
        try await client.from("payment_claims").insert(row).execute()
    }

    func paymentClaims(gymId: UUID) async throws -> [PaymentClaim] {
        let rows: [PaymentClaimRow] = try await client.rpc("get_payment_claims", params: GymIdParam(p_gym: gymId))
            .execute()
            .value
        return rows.map { row in
            PaymentClaim(id: row.id, userId: row.user_id, displayName: row.display_name ?? "",
                         periodMonth: row.period_month.flatMap { EventDates.date(from: $0) }, amount: row.amount,
                         method: MemberPaymentMethod(rawValue: row.method) ?? .cash,
                         reference: row.reference, note: row.note, createdAt: DateParsing.date(from: row.created_at))
        }
    }

    func confirmPaymentClaim(id: UUID) async throws {
        try await client.rpc("confirm_payment_claim", params: ClaimIdParam(p_claim: id)).execute()
    }

    func rejectPaymentClaim(id: UUID, note: String) async throws {
        try await client.rpc("reject_payment_claim", params: ClaimRejectParams(p_claim: id, p_note: note)).execute()
    }

    func revolutURL(gymId: UUID) async throws -> String? {
        let rows: [RevolutRow] = try await client.from("gyms")
            .select("revolut_url")
            .eq("id", value: gymId.uuidString)
            .limit(1)
            .execute()
            .value
        return rows.first?.revolut_url
    }

    func setRevolutURL(gymId: UUID, url: String) async throws {
        try await client.rpc("set_gym_revolut_url", params: RevolutParams(p_gym: gymId, p_url: url)).execute()
    }
}

struct StudentMembershipRow: Decodable {
    let gym_id: UUID
    let gym_name: String
    let gym_slug: String
    let revolut_url: String?
    let membership_id: UUID?
    let membership_name: String?
    let price: Double?
    let currency: String?
    let period: String?
    let paid_until: String?
    let next_due: String?
    let status: String
    let pending_claims: Int?
}
struct PaymentRecordRow: Decodable {
    let id: UUID
    let amount: Double
    let currency: String?
    let method: String
    let paid_at: String
    let period_month: String?
}
struct PaymentClaimInsert: Encodable {
    let gym_id: UUID
    let user_id: UUID
    let membership_id: UUID?
    let period_month: String
    let amount: Double?
    let method: String
    let reference: String
    let note: String?
}
struct PaymentClaimRow: Decodable {
    let id: UUID
    let user_id: UUID
    let display_name: String?
    let period_month: String?
    let amount: Double?
    let method: String
    let reference: String?
    let note: String?
    let created_at: String
}
struct ClaimIdParam: Encodable { let p_claim: UUID }
struct ClaimRejectParams: Encodable {
    let p_claim: UUID
    let p_note: String
}
struct RevolutRow: Decodable { let revolut_url: String? }
struct RevolutParams: Encodable {
    let p_gym: UUID
    let p_url: String
}

