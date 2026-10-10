import SwiftUI

struct CoachDetailView: View {
    @Environment(AppServices.self) private var services
    let coach: Coach
    @State private var gyms: [Gym] = []
    @State private var promotedBy: Coach?

    var body: some View {
        List {
            Section {
                HStack(spacing: 16) {
                    CoachPhotoView(url: coach.photoURL, size: 96)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(coach.fullName).font(.title2).bold()
                        if let latin = coach.fullNameLatin, latin != coach.fullName {
                            Text(latin).foregroundStyle(.secondary)
                        }
                        Text(LocalizedStringKey(coach.belt.localizedKey))
                        if coach.degree > 0 {
                            Text("coach.degree \(coach.degree)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if promotedBy != nil || coach.lineageText != nil {
                Section("coach.lineage") {
                    if let promotedBy {
                        NavigationLink(value: promotedBy) {
                            Text("coach.promotedBy \(promotedBy.fullName)")
                        }
                    }
                    if let lineage = coach.lineageText {
                        Text(lineage)
                    }
                }
            }

            if let bio = coach.bio, !bio.isEmpty {
                Section("coach.bio") {
                    Text(bio)
                }
            }

            Section("coach.achievements") {
                if coach.achievements.isEmpty {
                    Text("common.noData").foregroundStyle(.secondary)
                } else {
                    ForEach(coach.achievements, id: \.self) { achievement in
                        VStack(alignment: .leading) {
                            Text(achievement.title)
                            if let event = achievement.event {
                                Text(event).font(.subheadline).foregroundStyle(.secondary)
                            }
                            if let year = achievement.year {
                                Text(verbatim: String(year)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Section("coach.gyms") {
                if gyms.isEmpty {
                    Text("common.noData").foregroundStyle(.secondary)
                } else {
                    ForEach(gyms) { gym in
                        NavigationLink(value: gym) {
                            Text(gym.name)
                        }
                    }
                }
            }

            if let handle = coach.instagram, let url = Links.instagram(handle) {
                Section {
                    Link(destination: url) {
                        Label("common.instagram", systemImage: "camera")
                    }
                }
            }
        }
        .navigationTitle(coach.fullName)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await load()
        }
    }

    @MainActor
    private func load() async {
        var loaded: [Gym] = []
        for id in coach.gymIds {
            if let gym = try? await services.gyms.gym(id: id) {
                loaded.append(gym)
            }
        }
        gyms = loaded
        if let promoterId = coach.promotedByCoachId {
            promotedBy = try? await services.coaches.coach(id: promoterId)
        }
    }
}
