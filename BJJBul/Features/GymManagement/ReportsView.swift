import SwiftUI
import Charts

enum ReportPeriod: String, CaseIterable, Hashable {
    case week, month, threeMonths, custom

    var localizedKey: String { "reports.period.\(rawValue)" }
}

/// My gym → Reports (staff). All ranges are Sofia calendar days.
struct ReportsView: View {
    @Environment(AppServices.self) private var services
    let myGym: MyGym

    @State private var period: ReportPeriod = .month
    @State private var customFrom = Calendar.bulgaria.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    @State private var customTo = Date()
    @State private var visits: VisitsReport?
    @State private var classes: ClassesReport?
    @State private var revenue: RevenueReport?
    @State private var members: MembersReport?
    @State private var visitsCSV: URL?
    @State private var paymentsCSV: URL?
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var range: (from: Date, to: Date) {
        let cal = Calendar.bulgaria
        let today = cal.startOfDay(for: Date())
        switch period {
        case .week:
            let start = cal.dateInterval(of: .weekOfYear, for: today)?.start ?? today
            return (start, today)
        case .month:
            let start = cal.dateInterval(of: .month, for: today)?.start ?? today
            return (start, today)
        case .threeMonths:
            let monthStart = cal.dateInterval(of: .month, for: today)?.start ?? today
            return (cal.date(byAdding: .month, value: -2, to: monthStart) ?? monthStart, today)
        case .custom:
            let from = cal.startOfDay(for: min(customFrom, customTo))
            let to = cal.startOfDay(for: max(customFrom, customTo))
            return (from, to)
        }
    }

    private var bucket: ReportBucket {
        let days = Calendar.bulgaria.dateComponents([.day], from: range.from, to: range.to).day ?? 0
        if days <= 31 { return .day }
        if days <= 120 { return .week }
        return .month
    }

    private var chartUnit: Calendar.Component {
        switch bucket {
        case .day: return .day
        case .week: return .weekOfYear
        case .month: return .month
        }
    }

    private var loadKey: String {
        "\(period.rawValue)-\(EventDates.string(from: range.from))-\(EventDates.string(from: range.to))"
    }

    var body: some View {
        List {
            Section {
                Picker("reports.period", selection: $period) {
                    ForEach(ReportPeriod.allCases, id: \.self) { item in
                        Text(LocalizedStringKey(item.localizedKey)).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                if period == .custom {
                    DatePicker("reports.from", selection: $customFrom, in: ...Date(), displayedComponents: .date)
                    DatePicker("reports.to", selection: $customTo, in: ...Date(), displayedComponents: .date)
                }
                Text(verbatim: "\(BGDate.string(range.from, date: .medium, time: .none)) – \(BGDate.string(range.to, date: .medium, time: .none))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red) }
            }

            kpiSection
            visitsSection
            revenueSection
            heatmapSection
            topClassesSection
            overdueSection
            exportSection
        }
        .navigationTitle("reports.title")
        .overlay {
            if isLoading && visits == nil { ProgressView() }
        }
        .refreshable { await load() }
        .task(id: loadKey) { await load() }
    }

    // MARK: Sections

    private var kpiSection: some View {
        Section {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                kpi("reports.kpi.checkins", value: "\(visits?.totals.checkins ?? 0)", icon: "figure.martial.arts")
                kpi("reports.kpi.unique", value: "\(visits?.totals.unique_members ?? 0)", icon: "person.2")
                kpi("reports.kpi.revenue", value: euro(revenue?.total ?? 0), icon: "eurosign.circle")
                kpi("reports.kpi.mrr", value: euro(members?.mrr ?? 0), icon: "arrow.triangle.2.circlepath")
                kpi("reports.kpi.active", value: "\(members?.active ?? 0)", icon: "person.3")
                kpi("reports.kpi.new", value: "\(members?.new_this_month ?? 0)", icon: "person.badge.plus")
                kpi("reports.kpi.churned", value: "\(members?.churned ?? 0)", icon: "person.fill.xmark")
                kpi("reports.kpi.overdue", value: "\(members?.overdue ?? 0)", icon: "exclamationmark.circle")
                kpi("reports.kpi.guests", value: "\(visits?.totals.guests ?? 0)", icon: "ticket")
                kpi("reports.kpi.unpaid", value: "\(visits?.totals.unpaid ?? 0)", icon: "clock.badge.exclamationmark")
            }
            .padding(.vertical, 4)
        } header: {
            Text("reports.summary")
        } footer: {
            Text("reports.summary.footer \(revenue?.confirmed_claims ?? 0)")
        }
    }

    private func kpi(_ key: LocalizedStringKey, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(key, systemImage: icon).font(.caption).foregroundStyle(.secondary)
            Text(verbatim: value).font(.title3).bold()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.1)))
    }

    private var visitsSection: some View {
        Section {
            if let buckets = visits?.buckets, !buckets.isEmpty {
                Chart(buckets) { item in
                    BarMark(x: .value("Date", item.date, unit: chartUnit),
                            y: .value("Check-ins", item.checkins))
                        .foregroundStyle(Color.accentColor)
                    LineMark(x: .value("Date", item.date, unit: chartUnit),
                             y: .value("Members", item.unique_members))
                        .foregroundStyle(Color.orange)
                }
                .frame(height: 200)
                HStack(spacing: 16) {
                    legend(Color.accentColor, "reports.legend.checkins")
                    legend(Color.orange, "reports.legend.unique")
                }
            } else {
                Text("reports.noData").foregroundStyle(.secondary)
            }
        } header: {
            Text("reports.visits")
        }
    }

    private func legend(_ color: Color, _ key: LocalizedStringKey) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(key).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var revenueSection: some View {
        Section {
            if let rows = revenue?.rows, !rows.isEmpty {
                Chart(rows) { row in
                    BarMark(x: .value("Date", row.date, unit: chartUnit),
                            y: .value("EUR", row.amount))
                        .foregroundStyle(by: .value("Kind", String(localized: String.LocalizationValue("reports.kind.\(row.plan_kind)"))))
                }
                .frame(height: 200)
                ForEach(methodTotals, id: \.0) { item in
                    HStack {
                        Text(LocalizedStringKey("paymethod.\(item.0)"))
                        Spacer()
                        Text(verbatim: euro(item.1)).foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                }
            } else {
                Text("reports.noData").foregroundStyle(.secondary)
            }
        } header: {
            Text("reports.revenue")
        }
    }

    private var methodTotals: [(String, Double)] {
        var sums: [String: Double] = [:]
        for row in revenue?.rows ?? [] { sums[row.method, default: 0] += row.amount }
        return sums.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
    }

    private var heatmapSection: some View {
        Section {
            let cells = classes?.heatmap ?? []
            let hours = heatHours(cells)
            let maxVisits = max(cells.map { $0.visits }.max() ?? 1, 1)
            if cells.isEmpty {
                Text("reports.noData").foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    Grid(horizontalSpacing: 3, verticalSpacing: 3) {
                        GridRow {
                            Text(verbatim: "").frame(width: 28)
                            ForEach(hours, id: \.self) { hour in
                                Text(verbatim: "\(hour)").font(.system(size: 9)).frame(width: 22)
                            }
                        }
                        ForEach(1...7, id: \.self) { day in
                            GridRow {
                                Text(verbatim: String(Links.weekdayName(day).prefix(2)))
                                    .font(.caption2)
                                    .frame(width: 28, alignment: .leading)
                                ForEach(hours, id: \.self) { hour in
                                    let value = cells.first { $0.weekday == day && $0.hour == hour }?.visits ?? 0
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(value == 0 ? Color.secondary.opacity(0.08)
                                              : Color.accentColor.opacity(0.2 + 0.8 * Double(value) / Double(maxVisits)))
                                        .frame(width: 22, height: 22)
                                        .accessibilityLabel(Text(verbatim: "\(Links.weekdayName(day)) \(hour):00 – \(value)"))
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        } header: {
            Text("reports.heatmap")
        } footer: {
            Text("reports.heatmap.footer")
        }
    }

    private func heatHours(_ cells: [HeatCell]) -> [Int] {
        let used = cells.filter { $0.visits > 0 }.map { $0.hour }
        guard let low = used.min(), let high = used.max() else { return Array(6...22) }
        return Array(min(low, 7)...max(high, 21))
    }

    private var topClassesSection: some View {
        Section {
            let top = classes?.top_classes ?? []
            if top.isEmpty {
                Text("reports.noData").foregroundStyle(.secondary)
            }
            ForEach(top) { item in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: "\(Links.weekdayName(item.weekday)) \(item.start_time)–\(item.end_time)").font(.headline)
                        Text(LocalizedStringKey("class.\(item.type)")).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("reports.visitsCount \(item.visits)").font(.subheadline)
                        Text("reports.avg \(String(format: "%.1f", item.avg_per_session))")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("reports.topClasses")
        }
    }

    private var overdueSection: some View {
        Section {
            let list = members?.overdue_list ?? []
            if list.isEmpty {
                Text("gym.payments.allPaid").foregroundStyle(.secondary)
            }
            ForEach(list) { item in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: item.display_name ?? "—").font(.headline)
                        Text(verbatim: "\(item.plan_name ?? "") \(item.price.map { euro($0) } ?? "")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("reports.daysOverdue \(item.days_overdue ?? 0)")
                        .font(.caption).foregroundStyle(.red)
                }
            }
        } header: {
            Text("reports.overdue")
        }
    }

    private var exportSection: some View {
        Section {
            if let visitsCSV {
                ShareLink(item: visitsCSV) {
                    Label("reports.export.visits", systemImage: "square.and.arrow.up")
                }
            }
            if let paymentsCSV {
                ShareLink(item: paymentsCSV) {
                    Label("reports.export.payments", systemImage: "square.and.arrow.up")
                }
            }
            if visitsCSV == nil && paymentsCSV == nil {
                Text("reports.export.preparing").foregroundStyle(.secondary)
            }
        } header: {
            Text("reports.export")
        } footer: {
            Text("reports.export.footer")
        }
    }

    private func euro(_ value: Double) -> String {
        String(format: "%.0f €", value)
    }

    // MARK: Loading

    @MainActor
    private func load() async {
        isLoading = true
        defer { isLoading = false }
        let from = range.from
        let to = range.to
        let gymId = myGym.gymId
        let reports = services.reports
        do {
            visits = try await reports.visits(gymId: gymId, from: from, to: to, bucket: bucket)
            classes = try await reports.classes(gymId: gymId, from: from, to: to)
            revenue = try await reports.revenue(gymId: gymId, from: from, to: to, bucket: bucket)
            members = try await reports.members(gymId: gymId)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        let suffix = "\(myGym.slug)-\(EventDates.string(from: from))_\(EventDates.string(from: to))"
        if let rows = try? await reports.visitsList(gymId: gymId, from: from, to: to) {
            visitsCSV = ReportCSV.write(ReportCSV.visits(rows), name: "visits-\(suffix).csv")
        }
        if let rows = try? await reports.paymentsList(gymId: gymId, from: from, to: to) {
            paymentsCSV = ReportCSV.write(ReportCSV.payments(rows), name: "payments-\(suffix).csv")
        }
    }
}
