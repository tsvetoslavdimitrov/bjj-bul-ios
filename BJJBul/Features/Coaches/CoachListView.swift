import SwiftUI

struct CoachListView: View {
    @Environment(AppServices.self) private var services
    @State private var coaches: [Coach] = []

    var body: some View {
        NavigationStack {
            List(coaches) { coach in
                VStack(alignment: .leading) {
                    Text(coach.fullName).font(.headline)
                    Text(LocalizedStringKey(coach.belt.localizedKey))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("tab.coaches")
            .task {
                coaches = (try? await services.coaches.coaches()) ?? []
            }
        }
    }
}
