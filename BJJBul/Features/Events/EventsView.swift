import SwiftUI

struct EventsView: View {
    @Environment(AppServices.self) private var services
    @State private var events: [CompetitionEvent] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    /// Groups by month (Bulgarian time), keeping chronological order.
    private var sections: [(key: Date, title: String, items: [CompetitionEvent])] {
        let calendar = Calendar.bulgaria
        var result: [(key: Date, title: String, items: [CompetitionEvent])] = []
        for event in events {
            let comps = calendar.dateComponents([.year, .month], from: event.startsAt)
            guard let monthStart = calendar.date(from: comps) else { continue }
            if let index = result.firstIndex(where: { $0.key == monthStart }) {
                result[index].items.append(event)
            } else {
                result.append((key: monthStart, title: EventDates.monthTitle(monthStart), items: [event]))
            }
        }
        return result
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(sections, id: \.key) { section in
                    Section(section.title) {
                        ForEach(section.items) { event in
                            NavigationLink(value: event) {
                                EventRowView(event: event)
                            }
                        }
                    }
                }
                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
                Section {
                } footer: {
                    Text("events.source")
                }
            }
            .overlay {
                if isLoading && events.isEmpty {
                    ProgressView()
                } else if events.isEmpty && errorMessage == nil {
                    ContentUnavailableView("events.empty", systemImage: "calendar.badge.exclamationmark")
                }
            }
            .navigationTitle("tab.events")
            .navigationDestination(for: CompetitionEvent.self) { event in
                EventDetailView(event: event)
            }
            .refreshable {
                await load()
            }
            .task {
                await load()
            }
        }
    }

    @MainActor
    private func load() async {
        defer { isLoading = false }
        do {
            events = try await services.events.upcomingEvents()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct EventRowView: View {
    let event: CompetitionEvent

    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 0) {
                Text(event.startsAt.formatted(.dateTime.day().timeZone(Calendar.bulgaria.timeZone)))
                    .font(.title3).bold()
                Text(event.startsAt.formatted(.dateTime.weekday(.abbreviated).timeZone(Calendar.bulgaria.timeZone)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.name).font(.headline)
                if let city = event.city {
                    Label(city, systemImage: "mappin")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
