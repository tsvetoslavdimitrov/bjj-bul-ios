import Foundation

struct MockReportsService: ReportsService {
    private func days(_ from: Date, _ to: Date) -> [Date] {
        var result: [Date] = []
        var day = from
        while day <= to && result.count < 120 {
            result.append(day)
            day = Calendar.bulgaria.date(byAdding: .day, value: 1, to: day) ?? to.addingTimeInterval(1)
        }
        return result
    }

    func visits(gymId: UUID, from: Date, to: Date, bucket: ReportBucket) async throws -> VisitsReport {
        let buckets = days(from, to).enumerated().map { index, date in
            VisitBucket(bucket_start: EventDates.string(from: date), checkins: 12 + (index * 7) % 15,
                        unique_members: 10 + (index * 5) % 9, guests: index % 3, unpaid: index % 4 == 0 ? 1 : 0)
        }
        return VisitsReport(buckets: buckets,
                            totals: VisitTotals(checkins: buckets.reduce(0) { $0 + $1.checkins }, unique_members: 34,
                                                guests: buckets.reduce(0) { $0 + $1.guests },
                                                unpaid: buckets.reduce(0) { $0 + $1.unpaid }))
    }

    func classes(gymId: UUID, from: Date, to: Date) async throws -> ClassesReport {
        var cells: [HeatCell] = []
        for day in 1...6 {
            cells.append(HeatCell(weekday: day, hour: 19, visits: 10 + day * 2))
            cells.append(HeatCell(weekday: day, hour: 7, visits: day % 2 == 0 ? 4 : 0))
        }
        cells.append(HeatCell(weekday: 6, hour: 11, visits: 18))
        return ClassesReport(top_classes: [
            TopClass(class_id: UUID(), weekday: 1, start_time: "19:00", end_time: "20:30", type: "gi",
                     visits: 64, sessions: 4, avg_per_session: 16),
            TopClass(class_id: UUID(), weekday: 3, start_time: "19:00", end_time: "20:30", type: "nogi",
                     visits: 52, sessions: 4, avg_per_session: 13),
        ], heatmap: cells)
    }

    func revenue(gymId: UUID, from: Date, to: Date, bucket: ReportBucket) async throws -> RevenueReport {
        let start = EventDates.string(from: from)
        let rows = [
            RevenueRow(bucket_start: start, plan_kind: "subscription", method: "revolut", amount: 1200, payments: 20),
            RevenueRow(bucket_start: start, plan_kind: "subscription", method: "cash", amount: 600, payments: 10),
            RevenueRow(bucket_start: start, plan_kind: "one_off", method: "cash", amount: 300, payments: 3),
            RevenueRow(bucket_start: start, plan_kind: "drop_in", method: "revolut", amount: 90, payments: 6),
        ]
        return RevenueReport(rows: rows, total: 2190, payments: 39, confirmed_claims: 12)
    }

    func members(gymId: UUID) async throws -> MembersReport {
        MembersReport(active: 42, new_this_month: 5, churned: 6, overdue: 2, mrr: 2340,
                      overdue_list: [OverdueMember(user_id: UUID(), display_name: "Георги Петров", plan_name: "Monthly",
                                                   price: 60, due: "2026-09-01", days_overdue: 40)])
    }

    func visitsList(gymId: UUID, from: Date, to: Date) async throws -> [VisitListRow] {
        [VisitListRow(visit_date: EventDates.string(from: to), visit_time: "19:02", kind: "member",
                      display_name: "Иван Иванов", class_start: "19:00", class_type: "gi", unpaid: false)]
    }

    func paymentsList(gymId: UUID, from: Date, to: Date) async throws -> [PaymentListRow] {
        [PaymentListRow(paid_on: EventDates.string(from: to), source: "member", display_name: "Иван Иванов",
                        plan_name: "Monthly", plan_kind: "subscription", method: "cash", amount: 60, period_month: nil)]
    }
}
