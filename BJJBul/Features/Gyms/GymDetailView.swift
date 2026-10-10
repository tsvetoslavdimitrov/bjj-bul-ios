import SwiftUI

struct GymDetailView: View {
    @Environment(AppServices.self) private var services
    let gym: Gym
    @State private var schedule: [ClassSchedule] = []

    var body: some View {
        List {
            Section {
                Text(gym.address)
                if let phone = gym.phone { Text(phone) }
            }
            Section("gym.prices") {
                if let monthly = gym.priceMonthly {
                    Text("\(monthly.formatted()) \(gym.currency)")
                }
            }
            Section("gym.schedule") {
                ForEach(schedule) { item in
                    Text("\(item.weekday) · \(item.startTime)–\(item.endTime) · \(item.type.rawValue)")
                }
            }
        }
        .navigationTitle(gym.name)
        .task {
            schedule = (try? await services.gyms.schedule(gymId: gym.id)) ?? []
        }
    }
}
