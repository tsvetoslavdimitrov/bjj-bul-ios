import SwiftUI

struct ProfileView: View {
    @Environment(AppServices.self) private var services
    @State private var user: AppUser?

    var body: some View {
        NavigationStack {
            List {
                if let user {
                    Text(user.displayName).font(.headline)
                    Text(LocalizedStringKey(user.belt.localizedKey))
                } else {
                    Text("profile.signIn")
                }
            }
            .navigationTitle("tab.profile")
            .task {
                user = try? await services.users.currentUser()
            }
        }
    }
}
