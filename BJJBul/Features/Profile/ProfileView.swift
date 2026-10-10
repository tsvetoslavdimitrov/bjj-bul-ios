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
                Button("profile.edit") { showEditor = true }
            }

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
