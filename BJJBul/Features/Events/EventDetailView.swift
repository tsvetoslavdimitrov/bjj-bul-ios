import SwiftUI

struct EventDetailView: View {
    let event: CompetitionEvent
    @State private var isAdding = false
    @State private var alertMessage: LocalizedStringKey?
    @State private var showAlert = false

    var body: some View {
        List {
            if let imageURL = event.imageURL {
                Section {
                    AsyncImage(url: imageURL) { image in
                        image.resizable().scaledToFit()
                    } placeholder: {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.15))
                            .frame(height: 160)
                    }
                    .listRowInsets(EdgeInsets())
                }
            }

            Section {
                Text(event.name).font(.title2).bold()
                Label(EventDates.dayText(event), systemImage: "calendar")
                if event.venue != nil || event.city != nil {
                    Label([event.venue, event.city].compactMap { $0 }.joined(separator: ", "),
                          systemImage: "mappin.and.ellipse")
                }
            }

            if event.registrationDeadline != nil || event.registrationInfo != nil {
                Section("events.registration") {
                    if let deadline = event.registrationDeadline {
                        LabeledContent("events.registration.deadline",
                                       value: deadline.formatted(.dateTime.day().month().year().timeZone(Calendar.bulgaria.timeZone)))
                    }
                    if let info = event.registrationInfo {
                        Text(info)
                    }
                }
            }

            Section {
                Link(destination: event.registrationURL ?? event.url) {
                    Label("events.openSmoothcomp", systemImage: "safari")
                }
                Button {
                    Task { await addToCalendar() }
                } label: {
                    Label("events.addToCalendar", systemImage: "calendar.badge.plus")
                }
                .disabled(isAdding)
            } footer: {
                Text("events.registerNote")
            }
        }
        .navigationTitle(event.name)
        .navigationBarTitleDisplayMode(.inline)
        .alert(alertMessage ?? "", isPresented: $showAlert) {
            Button("common.close", role: .cancel) {}
        }
    }

    @MainActor
    private func addToCalendar() async {
        isAdding = true
        defer { isAdding = false }
        let result = await CalendarService.add(event)
        switch result {
        case .added:
            alertMessage = "events.calendar.added"
        case .denied:
            alertMessage = "events.calendar.denied"
        case .failed:
            alertMessage = "events.calendar.failed"
        }
        showAlert = true
    }
}
