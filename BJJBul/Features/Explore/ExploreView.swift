import SwiftUI

struct ExploreView: View {
    enum Mode: String, CaseIterable, Hashable {
        case map, gyms, coaches

        var localizedKey: LocalizedStringKey {
            switch self {
            case .map: return "explore.mode.map"
            case .gyms: return "tab.gyms"
            case .coaches: return "tab.coaches"
            }
        }
    }

    @Environment(AppServices.self) private var services
    @State private var mode: Mode = .map
    @State private var gyms: [Gym] = []
    @State private var cities: [City] = []
    @State private var cityId: UUID?
    @State private var showAddGym = false
    @State private var showSignInHint = false

    private var filteredGyms: [Gym] {
        guard let cityId else { return gyms }
        return gyms.filter { $0.cityId == cityId }
    }

    private var citiesWithGyms: [City] {
        let ids = Set(gyms.map { $0.cityId })
        return cities.filter { ids.contains($0.id) }
    }

    private var selectedCity: City? {
        guard let cityId else { return nil }
        return cities.first { $0.id == cityId }
    }

    private func cityName(_ id: UUID) -> String? {
        cities.first { $0.id == id }?.localizedName
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("explore.mode", selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { item in
                        Text(item.localizedKey).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)

                if mode != .coaches && !citiesWithGyms.isEmpty {
                    CityChipsView(cities: citiesWithGyms, selection: $cityId)
                        .padding(.vertical, 8)
                }

                switch mode {
                case .map:
                    GymMapView(gyms: filteredGyms.filter { $0.hasCoordinates },
                               focusCity: selectedCity,
                               cityName: cityName,
                               missingCount: filteredGyms.filter { !$0.hasCoordinates }.count,
                               onShowList: { mode = .gyms })
                case .gyms:
                    GymListContent(gyms: filteredGyms, cityName: cityName)
                case .coaches:
                    CoachListContent()
                }
            }
            .navigationTitle("tab.explore")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        if services.isSignedIn {
                            showAddGym = true
                        } else {
                            showSignInHint = true
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel(Text("contribute.addGym"))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        MarketplaceView()
                    } label: {
                        Label("shop.title", systemImage: "bag")
                    }
                }
            }
            .sheet(isPresented: $showAddGym) {
                AddGymView()
            }
            .alert("contribute.signInRequired", isPresented: $showSignInHint) {
                Button("common.close", role: .cancel) {}
            }
            .navigationDestination(for: Gym.self) { gym in
                GymDetailView(gym: gym)
            }
            .navigationDestination(for: Coach.self) { coach in
                CoachDetailView(coach: coach)
            }
            .task {
                await load()
            }
        }
    }

    @MainActor
    private func load() async {
        gyms = (try? await services.gyms.gyms(cityId: nil)) ?? []
        cities = (try? await services.gyms.cities()) ?? []
    }
}
