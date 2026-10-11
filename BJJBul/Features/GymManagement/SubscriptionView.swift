import SwiftUI
import UIKit

/// BJJ Bul subscription for a gym (B2B). Billing happens outside the app (Revolut / cash, later Stripe);
/// this screen only shows status and billing instructions. An admin marks payments in the dashboard.
struct SubscriptionView: View {
    @Environment(AppServices.self) private var services
    let myGym: MyGym
    @State private var subscription: GymSubscription?
    @State private var plans: [BJJBulPlan] = []
    @State private var copied = false
    @State private var isLoading = true

    private var plan: BJJBulPlan? {
        guard let id = subscription?.planId else { return plans.first }
        return plans.first { $0.id == id }
    }

    /// Payment reference = gym slug, so the admin can match the transfer.
    private var reference: String { myGym.slug }

    var body: some View {
        List {
            Section {
                if let subscription {
                    HStack {
                        Text("subscription.status")
                        Spacer()
                        Text(LocalizedStringKey(subscription.status.localizedKey))
                            .foregroundStyle(subscription.hasAccess ? Color.green : Color.red)
                    }
                    if subscription.status == .trialing, let end = subscription.trialEndsAt {
                        HStack {
                            Text("subscription.trialEnds")
                            Spacer()
                            Text(BGDate.string(end, date: .medium, time: .none)).foregroundStyle(.secondary)
                        }
                    }
                    if let end = subscription.currentPeriodEnd {
                        HStack {
                            Text("subscription.paidUntil")
                            Spacer()
                            Text(BGDate.string(end, date: .medium, time: .none)).foregroundStyle(.secondary)
                        }
                    }
                } else if !isLoading {
                    Text("subscription.none").foregroundStyle(.secondary)
                }
                if let plan {
                    HStack {
                        Text("subscription.plan")
                        Spacer()
                        Text(verbatim: "\(plan.name) · \(String(format: "%.2f", plan.priceMonthlyEUR)) EUR")
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("subscription.title")
            }

            Section {
                Text("subscription.billing.intro")
                    .font(.subheadline)
                HStack {
                    Text("subscription.reference")
                    Spacer()
                    Text(verbatim: reference).font(.body.monospaced()).bold()
                    Button {
                        UIPasteboard.general.string = reference
                        copied = true
                    } label: {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(Text("subscription.copyReference"))
                }
                if let url = URL(string: AppConfig.revolutMeURL) {
                    Link(destination: url) {
                        Label("subscription.revolut", systemImage: "arrow.up.right.square")
                    }
                }
                Text("subscription.cash")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if let mail = URL(string: "mailto:\(AppConfig.billingEmail)?subject=BJJ%20Bul%20billing%20\(reference)") {
                    Link(destination: mail) {
                        Label("subscription.contact", systemImage: "envelope")
                    }
                }
            } header: {
                Text("subscription.billing")
            } footer: {
                Text("subscription.billing.footer")
            }
        }
        .navigationTitle("subscription.title")
        .refreshable { await load() }
        .task { await load() }
    }

    @MainActor
    private func load() async {
        defer { isLoading = false }
        subscription = try? await services.gymManagement.subscription(gymId: myGym.gymId)
        plans = (try? await services.gymManagement.plans()) ?? []
    }
}
