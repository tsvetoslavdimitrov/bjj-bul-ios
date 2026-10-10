import SwiftUI

struct GymDetailView: View {
    @Environment(AppServices.self) private var services
    let gym: Gym
    @State private var schedule: [ClassSchedule] = []
    @State private var coaches: [Coach] = []
    @State private var showSuggest = false

    private var isFavorite: Bool { services.favoriteGymIds.contains(gym.id) }
    private var hasPrices: Bool { gym.priceDropIn != nil || gym.priceMonthly != nil || gym.priceKids != nil }
    private var scheduleDays: [Int] {
        Array(Set(schedule.map { $0.weekday })).sorted()
    }

    var body: some View {
        List {
            header
            contactSection
            if hasPrices {
                pricesSection
            }
            scheduleSection
            coachesSection
            Section {
                Button {
                    showSuggest = true
                } label: {
                    Label("gym.suggestEdit", systemImage: "square.and.pencil")
                }
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if !gym.verified {
                        Text("gym.unverified")
                    }
                    Text("gym.osmAttribution")
                }
            }
        }
        .navigationTitle(gym.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if services.isSignedIn {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await toggleFavorite() }
                    } label: {
                        Image(systemName: isFavorite ? "heart.fill" : "heart")
                    }
                    .accessibilityLabel(Text("gym.favorite"))
                }
            }
        }
        .sheet(isPresented: $showSuggest) {
            SuggestEditView(entityType: "gym", entityId: gym.id, title: gym.name)
        }
        .task {
            schedule = (try? await services.gyms.schedule(gymId: gym.id)) ?? []
            coaches = (try? await services.coaches.coaches(gymId: gym.id)) ?? []
        }
    }

    private var header: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text(gym.name).font(.title2).bold()
                if let latin = gym.nameLatin, latin != gym.name {
                    Text(latin).foregroundStyle(.secondary)
                }
                if let affiliation = gym.affiliation {
                    Label(affiliation, systemImage: "shield")
                        .font(.subheadline)
                }
                if gym.verified {
                    Label("gym.verified", systemImage: "checkmark.seal.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var contactSection: some View {
        Section("gym.contact") {
            if gym.address.isEmpty {
                Text("gym.address.missing").foregroundStyle(.secondary)
            } else {
                Text(gym.address)
            }
            if let url = Links.maps(for: gym), gym.hasCoordinates || !gym.address.isEmpty {
                Link(destination: url) {
                    Label("gym.openInMaps", systemImage: "map")
                }
            }
            if let phone = gym.phone, let url = Links.phone(phone) {
                Link(destination: url) {
                    Label(phone, systemImage: "phone")
                }
            }
            if let website = gym.website {
                Link(destination: website) {
                    Label("common.website", systemImage: "globe")
                }
            }
            if let handle = gym.instagram, let url = Links.instagram(handle) {
                Link(destination: url) {
                    Label("common.instagram", systemImage: "camera")
                }
            }
            if let facebook = gym.facebook, let url = Links.web(facebook) {
                Link(destination: url) {
                    Label("common.facebook", systemImage: "person.2")
                }
            }
            if gym.phone == nil && gym.website == nil && gym.instagram == nil && gym.facebook == nil {
                Text("gym.contact.missing").foregroundStyle(.secondary)
            }
        }
    }

    private var pricesSection: some View {
        Section("gym.prices") {
            if let price = gym.priceDropIn {
                LabeledContent("gym.price.dropIn", value: "\(price.formatted()) \(gym.currency)")
            }
            if let price = gym.priceMonthly {
                LabeledContent("gym.price.monthly", value: "\(price.formatted()) \(gym.currency)")
            }
            if let price = gym.priceKids {
                LabeledContent("gym.price.kids", value: "\(price.formatted()) \(gym.currency)")
            }
        }
    }

    @ViewBuilder
    private var scheduleSection: some View {
        if schedule.isEmpty {
            Section("gym.schedule") {
                Text("gym.schedule.empty").foregroundStyle(.secondary)
            }
        } else {
            ForEach(scheduleDays, id: \.self) { day in
                Section(Links.weekdayName(day)) {
                    ForEach(schedule.filter { $0.weekday == day }) { item in
                        HStack {
                            Text(verbatim: "\(item.startTime)–\(item.endTime)")
                                .monospacedDigit()
                            Spacer()
                            Text(LocalizedStringKey("class.\(item.type.rawValue)"))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var coachesSection: some View {
        Section("gym.coaches") {
            if coaches.isEmpty {
                Text("common.noData").foregroundStyle(.secondary)
            } else {
                ForEach(coaches) { coach in
                    NavigationLink(value: coach) {
                        CoachRowView(coach: coach)
                    }
                }
            }
        }
    }

    @MainActor
    private func toggleFavorite() async {
        let newValue = !isFavorite
        if newValue {
            services.favoriteGymIds.insert(gym.id)
        } else {
            services.favoriteGymIds.remove(gym.id)
        }
        do {
            try await services.users.setFavorite(gymId: gym.id, isFavorite: newValue)
        } catch {
            // Revert on failure.
            if newValue {
                services.favoriteGymIds.remove(gym.id)
            } else {
                services.favoriteGymIds.insert(gym.id)
            }
        }
    }
}
