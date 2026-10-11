import Foundation

struct VisitBucket: Decodable, Identifiable, Hashable {
    let bucket_start: String
    let checkins: Int
    let unique_members: Int
    let guests: Int
    let unpaid: Int

    var id: String { bucket_start }
    var date: Date { EventDates.date(from: bucket_start) ?? Date() }
}

struct VisitTotals: Decodable, Hashable {
    let checkins: Int
    let unique_members: Int
    let guests: Int
    let unpaid: Int
}

struct VisitsReport: Decodable, Hashable {
    let buckets: [VisitBucket]
    let totals: VisitTotals
}

struct TopClass: Decodable, Identifiable, Hashable {
    let class_id: UUID
    let weekday: Int
    let start_time: String
    let end_time: String
    let type: String
    let visits: Int
    let sessions: Int
    let avg_per_session: Double

    var id: UUID { class_id }
}

struct HeatCell: Decodable, Hashable {
    let weekday: Int
    let hour: Int
    let visits: Int
}

struct ClassesReport: Decodable, Hashable {
    let top_classes: [TopClass]
    let heatmap: [HeatCell]
}

struct RevenueRow: Decodable, Identifiable, Hashable {
    let bucket_start: String
    let plan_kind: String
    let method: String
    let amount: Double
    let payments: Int

    var id: String { "\(bucket_start)-\(plan_kind)-\(method)" }
    var date: Date { EventDates.date(from: bucket_start) ?? Date() }
}

struct RevenueReport: Decodable, Hashable {
    let rows: [RevenueRow]
    let total: Double
    let payments: Int
    let confirmed_claims: Int
}

struct OverdueMember: Decodable, Identifiable, Hashable {
    let user_id: UUID
    let display_name: String?
    let plan_name: String?
    let price: Double?
    let due: String?
    let days_overdue: Int?

    var id: UUID { user_id }
}

struct MembersReport: Decodable, Hashable {
    let active: Int
    let new_this_month: Int
    let churned: Int
    let overdue: Int
    let mrr: Double
    let overdue_list: [OverdueMember]
}

struct VisitListRow: Decodable, Hashable {
    let visit_date: String
    let visit_time: String?
    let kind: String
    let display_name: String?
    let class_start: String?
    let class_type: String?
    let unpaid: Bool?
}

struct PaymentListRow: Decodable, Hashable {
    let paid_on: String
    let source: String
    let display_name: String?
    let plan_name: String?
    let plan_kind: String
    let method: String?
    let amount: Double
    let period_month: String?
}

enum ReportBucket: String {
    case day, week, month
}

enum ReportCSV {
    static func escape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }

    static func visits(_ rows: [VisitListRow]) -> String {
        var lines = ["date,time,kind,name,class_start,class_type,unpaid"]
        for r in rows {
            lines.append([r.visit_date, r.visit_time ?? "", r.kind, r.display_name ?? "", r.class_start ?? "",
                          r.class_type ?? "", (r.unpaid ?? false) ? "yes" : "no"].map(escape).joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func payments(_ rows: [PaymentListRow]) -> String {
        var lines = ["date,source,name,plan,plan_kind,method,amount_eur,period_month"]
        for r in rows {
            lines.append([r.paid_on, r.source, r.display_name ?? "", r.plan_name ?? "", r.plan_kind, r.method ?? "",
                          String(format: "%.2f", r.amount), r.period_month ?? ""].map(escape).joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Writes to a temp file with a readable name (UTF-8 with BOM so Excel opens Cyrillic correctly).
    static func write(_ text: String, name: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(Data(text.utf8))
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}
