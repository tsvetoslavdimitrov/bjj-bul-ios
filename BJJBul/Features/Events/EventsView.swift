import SwiftUI

/// Events tab: competitions (Smoothcomp) and community open mats.
struct EventsView: View {
    enum Segment: String, CaseIterable, Hashable {
        case competitions, openMats

        var localizedKey: LocalizedStringKey {
            switch self {
            case .competitions: return "events.segment.competitions"
            case .openMats: return "events.segment.openMats"
            }
        }
    }

    @State private var segment: Segment = .competitions

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("events.segment", selection: $segment) {
                    ForEach(Segment.allCases, id: \.self) { item in
                        Text(item.localizedKey).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)
                switch segment {
                case .competitions:
                    CompetitionsListContent()
                case .openMats:
                    OpenMatsListContent()
                }
            }
            .navigationTitle("tab.events")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: CompetitionEvent.self) { event in
                EventDetailView(event: event)
            }
            .navigationDestination(for: Gym.self) { gym in
                GymDetailView(gym: gym)
            }
        }
    }
}

struct CompetitionsListContent: View {
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
            .refreshable {
                await load()
            }
            .task {
                await load()
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
                Text(event.startsAt.formatted(Date.FormatStyle(timeZone: Calendar.bulgaria.timeZone).day()))
                    .font(.title3).bold()
                Text(event.startsAt.formatted(Date.FormatStyle(timeZone: Calendar.bulgaria.timeZone).weekday(.abbreviated)))
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
