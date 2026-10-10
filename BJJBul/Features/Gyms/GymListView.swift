import SwiftUI

struct GymListView: View {
    @Environment(AppServices.self) private var services
    @State private var gyms: [Gym] = []
    @State private var searchText = ""

    private var filtered: [Gym] {
        guard !searchText.isEmpty else { return gyms }
        return gyms.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
                || ($0.nameLatin ?? "").localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            List(filtered) { gym in
                NavigationLink(value: gym) {
                    VStack(alignment: .leading) {
                        Text(gym.name).font(.headline)
                        Text(gym.address).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("tab.gyms")
            .navigationDestination(for: Gym.self) { gym in
                GymDetailView(gym: gym)
            }
            .searchable(text: $searchText)
            .task {
                gyms = (try? await services.gyms.gyms(cityId: nil)) ?? []
            }
        }
    }
}
