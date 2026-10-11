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
                            Text(LocalizedStringKey(item.status.localizedKey))
                                .foregroundStyle(MyPaymentsView.color(item.status))
                            if let due = item.nextDue {
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
                row("mypay.plan", membership.membershipName ?? String(localized: "gym.membership.none"))
                if let price = membership.price {
                    row("mypay.price", String(format: "%.2f %@", price, membership.currency))
                }
                HStack {
                    Text("mypay.status")
                    Spacer()
                    Text(LocalizedStringKey(membership.status.localizedKey))
                        .foregroundStyle(MyPaymentsView.color(membership.status))
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
            PaymentClaimView(membership: membership, reference: reference) {
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
    let membership: StudentMembership
    let reference: String
    let onSent: () -> Void
    @State private var method: MemberPaymentMethod = .revolut
    @State private var amountText: String
    @State private var note = ""
    @State private var errorMessage: String?
    @State private var isSending = false

    init(membership: StudentMembership, reference: String, onSent: @escaping () -> Void) {
        self.membership = membership
        self.reference = reference
        self.onSent = onSent
        _amountText = State(initialValue: membership.price.map { String(format: "%.2f", $0) } ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("gym.payments.method", selection: $method) {
                        ForEach(MemberPaymentMethod.allCases, id: \.self) { item in
                            Text(LocalizedStringKey(item.localizedKey)).tag(item)
                        }
                    }
                    TextField("gym.payments.amount", text: $amountText).keyboardType(.decimalPad)
                    HStack {
                        Text("mypay.period")
                        Spacer()
                        Text(verbatim: EventDates.monthTitle(membership.periodMonth)).foregroundStyle(.secondary)
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
        }
    }

    @MainActor
    private func send() async {
        isSending = true
        defer { isSending = false }
        let amount = Double(amountText.replacingOccurrences(of: ",", with: "."))
        let draft = PaymentClaimDraft(gymId: membership.gymId, membershipId: membership.membershipId,
                                      periodMonth: membership.periodMonth, amount: amount, method: method,
                                      reference: reference, note: note)
        do {
            try await services.gymManagement.submitPaymentClaim(draft)
            onSent()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
