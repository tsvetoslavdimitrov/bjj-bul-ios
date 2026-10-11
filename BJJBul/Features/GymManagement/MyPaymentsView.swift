import SwiftUI
import UIKit

/// Profile → My payments: one card per gym where I'm a student.
struct MyPaymentsView: View {
    @Environment(AppServices.self) private var services
    @State private var memberships: [StudentMembership] = []
    @State private var isLoading = true

    var body: some View {
        List {
            if memberships.isEmpty && !isLoading {
                Text("mypay.none").foregroundStyle(.secondary)
            }
            ForEach(memberships) { item in
                NavigationLink {
                    StudentPaymentDetailView(membership: item)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.gymName).font(.headline)
                        HStack(spacing: 6) {
                            if item.memberStatus == .pending {
                                Text("memberstatus.pending").foregroundStyle(.orange)
                            } else if item.status != .none {
                                Text(LocalizedStringKey(item.status.localizedKey))
                                    .foregroundStyle(MyPaymentsView.color(item.status))
                            }
                            if item.passCredits > 0 {
                                Text("pass.creditsLeft \(item.passCredits)")
                            }
                            if let due = item.nextDue, item.status != .none {
                                Text(verbatim: "·")
                                Text("mypay.nextDue \(BGDate.string(due, date: .medium, time: .none))")
                            }
                        }
                        .font(.caption)
                    }
                }
            }
        }
        .navigationTitle("mypay.title")
        .refreshable { await load() }
        .task { await load() }
    }

    static func color(_ status: PaymentPeriodStatus) -> Color {
        switch status {
        case .paid: return .green
        case .due: return .orange
        case .overdue: return .red
        case .none: return .secondary
        }
    }

    @MainActor
    private func load() async {
        defer { isLoading = false }
        memberships = (try? await services.gymManagement.myStudentMemberships()) ?? []
    }
}

struct StudentPaymentDetailView: View {
    @Environment(AppServices.self) private var services
    let membership: StudentMembership
    @State private var history: [PaymentRecord] = []
    @State private var copied = false
    @State private var showClaim = false
    @State private var claimSent = false

    private var reference: String {
        membership.reference(userId: services.currentUser?.id ?? UUID())
    }

    var body: some View {
        List {
            Section {
                BJJPassCard(membership: membership)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
            Section {
                row("mypay.plan", membership.membershipName ?? String(localized: "gym.membership.none"))
                if let price = membership.price {
                    row("mypay.price", String(format: "%.2f %@", price, membership.currency))
                }
                if membership.status != .none {
                    HStack {
                        Text("mypay.status")
                        Spacer()
                        Text(LocalizedStringKey(membership.status.localizedKey))
                            .foregroundStyle(MyPaymentsView.color(membership.status))
                    }
                }
                if let paidUntil = membership.paidUntil {
                    row("mypay.paidUntil", BGDate.string(paidUntil, date: .medium, time: .none))
                }
                if let due = membership.nextDue {
                    row("mypay.nextDueLabel", BGDate.string(due, date: .medium, time: .none))
                }
                if membership.pendingClaims > 0 || claimSent {
                    Label("mypay.claimPending", systemImage: "hourglass")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            } header: {
                Text(membership.gymName)
            }

            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("mypay.reference").font(.caption).foregroundStyle(.secondary)
                        Text(verbatim: reference).font(.callout.monospaced())
                    }
                    Spacer()
                    Button {
                        UIPasteboard.general.string = reference
                        copied = true
                    } label: {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(Text("subscription.copyReference"))
                }
                if let url = membership.revolutURL {
                    Link(destination: url) {
                        Label("mypay.payRevolut", systemImage: "arrow.up.right.square")
                    }
                } else {
                    Text("mypay.noRevolut").font(.footnote).foregroundStyle(.secondary)
                }
                Text("mypay.cash").font(.footnote)
                Button {
                    showClaim = true
                } label: {
                    Label("mypay.ivePaid", systemImage: "checkmark.seal")
                }
                .disabled(claimSent)
            } header: {
                Text("mypay.howToPay")
            } footer: {
                Text("mypay.confirmNote")
            }

            Section {
                if history.isEmpty {
                    Text("mypay.noHistory").foregroundStyle(.secondary)
                }
                ForEach(history) { item in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: String(format: "%.2f %@", item.amount, item.currency)).font(.headline)
                            HStack(spacing: 4) {
                                Text(LocalizedStringKey(item.method.localizedKey))
                                Text(verbatim: "· \(BGDate.string(item.paidAt, date: .medium, time: .none))")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let month = item.periodMonth {
                            Text(verbatim: EventDates.monthTitle(month))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("mypay.history")
            }
        }
        .navigationTitle("mypay.title")
        .sheet(isPresented: $showClaim) {
            PaymentClaimView(gymId: membership.gymId, gymSlug: membership.gymSlug,
                             defaultPlanId: membership.membershipId, defaultPrice: membership.price,
                             periodMonth: membership.periodMonth) {
                claimSent = true
            }
        }
        .task {
            history = (try? await services.gymManagement.myPayments(gymId: membership.gymId)) ?? []
        }
    }

    private func row(_ key: LocalizedStringKey, _ value: String) -> some View {
        HStack {
            Text(key)
            Spacer()
            Text(verbatim: value).foregroundStyle(.secondary)
        }
    }
}

struct PaymentClaimView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    let gymId: UUID
    let gymSlug: String
    let defaultPlanId: UUID?
    let defaultPrice: Double?
    let periodMonth: Date
    let onSent: () -> Void
    @State private var plans: [GymPassPlan] = []
    @State private var planId: UUID?
    @State private var method: MemberPaymentMethod = .revolut
    @State private var amountText: String
    @State private var note = ""
    @State private var errorMessage: String?
    @State private var isSending = false

    init(gymId: UUID, gymSlug: String, defaultPlanId: UUID?, defaultPrice: Double?, periodMonth: Date,
         onSent: @escaping () -> Void) {
        self.gymId = gymId
        self.gymSlug = gymSlug
        self.defaultPlanId = defaultPlanId
        self.defaultPrice = defaultPrice
        self.periodMonth = periodMonth
        self.onSent = onSent
        _planId = State(initialValue: defaultPlanId)
        _amountText = State(initialValue: defaultPrice.map { String(format: "%.2f", $0) } ?? "")
    }

    private var reference: String {
        PassReference.make(slug: gymSlug, userId: services.currentUser?.id ?? UUID(), month: periodMonth)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if !plans.isEmpty {
                        Picker("gym.membership", selection: $planId) {
                            Text("gym.membership.none").tag(UUID?.none)
                            ForEach(plans) { plan in
                                Text(verbatim: "\(plan.name) · \(String(format: "%.2f", plan.price)) \(plan.currency)")
                                    .tag(UUID?.some(plan.id))
                            }
                        }
                    }
                    Picker("gym.payments.method", selection: $method) {
                        ForEach(MemberPaymentMethod.allCases, id: \.self) { item in
                            Text(LocalizedStringKey(item.localizedKey)).tag(item)
                        }
                    }
                    TextField("gym.payments.amount", text: $amountText).keyboardType(.decimalPad)
                    HStack {
                        Text("mypay.period")
                        Spacer()
                        Text(verbatim: EventDates.monthTitle(periodMonth)).foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("mypay.reference")
                        Spacer()
                        Text(verbatim: reference).font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                    TextField("gym.payments.note", text: $note)
                } footer: {
                    Text("mypay.confirmNote")
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
            }
            .navigationTitle("mypay.ivePaid")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("contribute.submit") {
                        Task { await send() }
                    }
                    .disabled(isSending || note.count > 300)
                }
            }
            .onChange(of: planId) { _, newValue in
                if let plan = plans.first(where: { $0.id == newValue }) {
                    amountText = String(format: "%.2f", plan.price)
                }
            }
            .task {
                plans = (try? await services.gymManagement.gymPassPlans(gymId: gymId)) ?? []
            }
        }
    }

    @MainActor
    private func send() async {
        isSending = true
        defer { isSending = false }
        let amount = Double(amountText.replacingOccurrences(of: ",", with: "."))
        let draft = PaymentClaimDraft(gymId: gymId, membershipId: planId, periodMonth: periodMonth,
                                      amount: amount, method: method, reference: reference, note: note)
        do {
            try await services.gymManagement.submitPaymentClaim(draft)
            onSent()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// The BJJ Pass card: subscription status or credits left, expiry.
struct BJJPassCard: View {
    let membership: StudentMembership

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("pass.brand", systemImage: "ticket.fill")
                    .font(.headline)
                Spacer()
                if membership.memberStatus == .pending {
                    Text("memberstatus.pending").font(.caption).bold()
                } else if membership.status != .none {
                    Text(LocalizedStringKey(membership.status.localizedKey)).font(.caption).bold()
                }
            }
            Text(verbatim: membership.gymName).font(.title3).bold()
            if let name = membership.membershipName, membership.kind == .subscription, membership.status != .none {
                Text(verbatim: name).font(.subheadline)
                if let due = membership.nextDue {
                    Text("mypay.nextDue \(BGDate.string(due, date: .medium, time: .none))").font(.caption)
                }
            }
            if membership.passCredits > 0 {
                Text("pass.creditsLeft \(membership.passCredits)").font(.subheadline).bold()
                if let expires = membership.passExpiresAt {
                    Text("pass.expires \(BGDate.string(expires, date: .medium, time: .none))").font(.caption)
                }
            } else if membership.status == .none {
                Text("pass.noActive").font(.caption)
            }
        }
        .foregroundStyle(.white)
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(LinearGradient(colors: [Color.black, BJJPassCard.tint(membership)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
        )
    }

    static func tint(_ membership: StudentMembership) -> Color {
        if membership.passCredits > 0 || membership.status == .paid { return Color(red: 0.0, green: 0.45, blue: 0.3) }
        if membership.status == .overdue { return Color(red: 0.7, green: 0.1, blue: 0.1) }
        return Color(red: 0.75, green: 0.45, blue: 0.0)
    }
}

/// Visitors (and members) buy a one-off pass for a gym from its page.
struct GymPassPurchaseView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    let gymId: UUID
    let gymName: String
    @State private var plans: [GymPassPlan] = []
    @State private var selected: GymPassPlan?
    @State private var copied = false
    @State private var showClaim = false
    @State private var sent = false
    @State private var isLoading = true

    private var oneOff: [GymPassPlan] { plans.filter { $0.kind == .oneOff } }

    private var reference: String {
        PassReference.make(slug: selected?.gymSlug ?? plans.first?.gymSlug ?? "gym",
                           userId: services.currentUser?.id ?? UUID(), month: Date())
    }

    var body: some View {
        NavigationStack {
            List {
                if sent {
                    Section {
                        Label("pass.buy.sent", systemImage: "checkmark.circle").foregroundStyle(.green)
                    }
                }
                Section {
                    if oneOff.isEmpty && !isLoading {
                        Text("pass.buy.none").foregroundStyle(.secondary)
                    }
                    ForEach(oneOff) { plan in
                        Button {
                            selected = plan
                        } label: {
                            HStack {
                                Image(systemName: selected?.id == plan.id ? "largecircle.fill.circle" : "circle")
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(verbatim: plan.name).font(.headline)
                                    Text("pass.summary \(plan.classCredits ?? 1) \(plan.validityDays ?? 30)")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(verbatim: String(format: "%.2f %@", plan.price, plan.currency))
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("pass.buy.choose")
                }
                if let selected {
                    Section {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("mypay.reference").font(.caption).foregroundStyle(.secondary)
                                Text(verbatim: reference).font(.callout.monospaced())
                            }
                            Spacer()
                            Button {
                                UIPasteboard.general.string = reference
                                copied = true
                            } label: {
                                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            }
                            .buttonStyle(.borderless)
                        }
                        if let url = selected.revolutURL {
                            Link(destination: url) {
                                Label("mypay.payRevolut", systemImage: "arrow.up.right.square")
                            }
                        } else {
                            Text("mypay.noRevolut").font(.footnote).foregroundStyle(.secondary)
                        }
                        Text("mypay.cash").font(.footnote)
                        Button {
                            showClaim = true
                        } label: {
                            Label("mypay.ivePaid", systemImage: "checkmark.seal")
                        }
                        .disabled(sent)
                    } header: {
                        Text("mypay.howToPay")
                    } footer: {
                        Text("pass.buy.footer")
                    }
                }
            }
            .navigationTitle(Text(verbatim: gymName))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.close") { dismiss() }
                }
            }
            .sheet(isPresented: $showClaim) {
                if let selected {
                    PaymentClaimView(gymId: gymId, gymSlug: selected.gymSlug, defaultPlanId: selected.id,
                                     defaultPrice: selected.price, periodMonth: Date()) {
                        sent = true
                    }
                }
            }
            .task {
                defer { isLoading = false }
                plans = (try? await services.gymManagement.gymPassPlans(gymId: gymId)) ?? []
                selected = oneOff.first
            }
        }
    }
}
