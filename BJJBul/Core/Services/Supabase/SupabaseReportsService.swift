import Foundation
import Supabase

struct SupabaseReportsService: ReportsService {
    let client: SupabaseClient

    private struct RangeParams: Encodable {
        let p_gym: UUID
        let p_from: String
        let p_to: String
    }
    private struct BucketParams: Encodable {
        let p_gym: UUID
        let p_from: String
        let p_to: String
        let p_bucket: String
    }
    private struct GymOnly: Encodable { let p_gym: UUID }

    private func day(_ date: Date) -> String { EventDates.string(from: date) }

    func visits(gymId: UUID, from: Date, to: Date, bucket: ReportBucket) async throws -> VisitsReport {
        let params = BucketParams(p_gym: gymId, p_from: day(from), p_to: day(to), p_bucket: bucket.rawValue)
        let report: VisitsReport = try await client.rpc("gym_report_visits", params: params).execute().value
        return report
    }

    func classes(gymId: UUID, from: Date, to: Date) async throws -> ClassesReport {
        let report: ClassesReport = try await client.rpc("gym_report_classes",
                                                         params: RangeParams(p_gym: gymId, p_from: day(from), p_to: day(to)))
            .execute().value
        return report
    }

    func revenue(gymId: UUID, from: Date, to: Date, bucket: ReportBucket) async throws -> RevenueReport {
        let params = BucketParams(p_gym: gymId, p_from: day(from), p_to: day(to), p_bucket: bucket.rawValue)
        let report: RevenueReport = try await client.rpc("gym_report_revenue", params: params).execute().value
        return report
    }

    func members(gymId: UUID) async throws -> MembersReport {
        let report: MembersReport = try await client.rpc("gym_report_members", params: GymOnly(p_gym: gymId)).execute().value
        return report
    }

    func visitsList(gymId: UUID, from: Date, to: Date) async throws -> [VisitListRow] {
        let rows: [VisitListRow] = try await client.rpc("gym_report_visits_list",
                                                        params: RangeParams(p_gym: gymId, p_from: day(from), p_to: day(to)))
            .execute().value
        return rows
    }

    func paymentsList(gymId: UUID, from: Date, to: Date) async throws -> [PaymentListRow] {
        let rows: [PaymentListRow] = try await client.rpc("gym_report_payments_list",
                                                          params: RangeParams(p_gym: gymId, p_from: day(from), p_to: day(to)))
            .execute().value
        return rows
    }
}
