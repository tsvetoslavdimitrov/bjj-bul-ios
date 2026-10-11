import SwiftUI

struct ProfileView: View {
    @Environment(AppServices.self) private var services
    @State private var showEditor = false
    @State private var confirmDelete = false
    @State private var homeGym: Gym?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if let user = services.currentUser {
                    profileList(user)
                } else {
                    SignInView()
                }
            }
            .navigationTitle("tab.profile")
        }
    }

    private func profileList(_ user: AppUser) -> some View {
        List {
            Section {
                if user.displayName.isEmpty {
                    Text("profile.noName").font(.headline).foregroundStyle(.secondary)
                } else {
                    Text(user.displayName).font(.headline)
                }
                HStack {
                    Text(LocalizedStringKey(user.belt.localizedKey))
                    Spacer()
                    Text("profile.stripes \(user.stripes)")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("profile.homeGym")
                    Spacer()
                    if let homeGym {
                        Text(homeGym.name).foregroundStyle(.secondary)
                    } else {
                        Text("profile.homeGym.none").foregroundStyle(.secondary)
                    }
                }
                if let team = user.team, !team.isEmpty {
                    HStack {
                        Text("athlete.team")
                        Spacer()
                        Text(team).foregroundStyle(.secondary)
                    }
                }
                Button("profile.edit") { showEditor = true }
            }

            Section {
                AthleteRecordCard(userId: user.id, smoothcompURL: user.smoothcompProfileURL, isMe: true)
                    .listRowInsets(EdgeInsets())
            }

            Section {
                NavigationLink {
                    MyGymListView()
                } label: {
                    Label("gym.my", systemImage: "building.columns")
                }
                NavigationLink {
                    MemberQRView()
                } label: {
                    Label("qr.title", systemImage: "qrcode")
                }
                NavigationLink {
                    MyPaymentsView()
                } label: {
                    Label("mypay.title", systemImage: "ticket")
                }
                NavigationLink {
                    MarketplaceView()
                } label: {
                    Label("shop.title", systemImage: "bag")
                }
                NavigationLink {
                    MyOrdersView()
                } label: {
                    Label("shop.myOrders", systemImage: "shippingbox")
                }
                NavigationLink {
                    MyPartnerStoresView()
                } label: {
                    Label("partner.myStore", systemImage: "storefront")
                }
            }

            Section {
                NavigationLink {
                    AskBJJView()
                } label: {
                    Label("ai.title", systemImage: "sparkles")
                }
                NavigationLink {
                    MyRequestsView()
                } label: {
                    Label("dropin.myRequests", systemImage: "tray")
                }
                NavigationLink {
                    NotificationsView()
                } label: {
                    Label("notifications.title", systemImage: "bell")
                }
                NavigationLink {
                    NotificationSettingsView()
                } label: {
                    Label("notifications.settings", systemImage: "bell.badge")
                }
            }

            LegalLinksSection()

            Section {
                Button("profile.signOut") {
                    Task { await signOut() }
                }
                Button("profile.delete", role: .destructive) {
                    confirmDelete = true
                }
            } footer: {
                Text("profile.delete.footer")
            }

            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
        }
        .task(id: user.homeGymId) {
            if let id = user.homeGymId {
                homeGym = try? await services.gyms.gym(id: id)
            } else {
                homeGym = nil
            }
        }
        .sheet(isPresented: $showEditor) {
            ProfileEditView(user: user)
        }
        .confirmationDialog("profile.delete.confirmTitle", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("profile.delete.confirm", role: .destructive) {
                Task { await deleteAccount() }
            }
            Button("common.cancel", role: .cancel) {}
        } message: {
            Text("profile.delete.message")
        }
    }

    @MainActor
    private func signOut() async {
        do {
            try await services.auth.signOut()
        } catch {
            errorMessage = error.localizedDescription
        }
        await services.refreshSession()
    }

    @MainActor
    private func deleteAccount() async {
        do {
            try await services.auth.deleteAccount()
            await services.refreshSession()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
