import SwiftUI

/// Gym directory list (embedded in Explore's NavigationStack).
struct GymListContent: View {
    let gyms: [Gym]
    let cityName: (UUID) -> String?
    @State private var searchText = ""
    @State private var onlyMissing = false

    private var filtered: [Gym] {
        gyms.filter { gym in
            let matchesSearch = searchText.isEmpty
                || gym.name.localizedCaseInsensitiveContains(searchText)
                || (gym.nameLatin ?? "").localizedCaseInsensitiveContains(searchText)
                || (gym.affiliation ?? "").localizedCaseInsensitiveContains(searchText)
            let matchesMissing = !onlyMissing || !gym.hasCoordinates
            return matchesSearch && matchesMissing
        }
    }

    var body: some View {
        List {
            Toggle("explore.onlyMissing", isOn: $onlyMissing)
                .font(.subheadline)
            ForEach(filtered) { gym in
                NavigationLink(value: gym) {
                    GymCardView(gym: gym, cityName: cityName(gym.cityId))
                }
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .searchable(text: $searchText)
        .overlay {
            if filtered.isEmpty {
                ContentUnavailableView("explore.noGyms", systemImage: "building.2")
            }
        }
    }
}
