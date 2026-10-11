import SwiftUI

struct DropInRequestView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    let gym: Gym
    let schedule: [ClassSchedule]

    @State private var hasDate = true
    @State private var date = Date().addingTimeInterval(24 * 3600)
    @State private var preferredClass = ""
    @State private var message = ""
    @State private var isSending = false
    @State private var sent = false
    @State private var errorMessage: String?

    private var classOptions: [String] {
        schedule
            .sorted { ($0.weekday, $0.startTime) < ($1.weekday, $1.startTime) }
            .map { item in
                "\(Links.weekdayName(item.weekday)) \(item.startTime)"
            }
    }

    var body: some View {
        NavigationStack {
            Form {
                if sent {
                    Section {
                        Label("dropin.sent", systemImage: "checkmark.circle")
                            .foregroundStyle(.green)
                        Text("dropin.sent.detail")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section {
                        Text(gym.name).font(.headline)
                    }
                    Section("dropin.when") {
                        Toggle("dropin.pickDate", isOn: $hasDate)
                        if hasDate {
                            DatePicker("dropin.date", selection: $date, in: Date()..., displayedComponents: .date)
                        }
                        if !classOptions.isEmpty {
                            Picker("dropin.class", selection: $preferredClass) {
                                Text("dropin.class.any").tag("")
                                ForEach(classOptions, id: \.self) { option in
                                    Text(verbatim: option).tag(option)
                                }
                            }
                        } else {
                            TextField("dropin.class", text: $preferredClass)
                        }
                    }
                    Section {
                        TextEditor(text: $message)
                            .frame(minHeight: 100)
                    } header: {
Text("dropin.message")
} footer: {
                        Text("dropin.privacy")
                    }
                    if let errorMessage {
                        Section {
                            Text(errorMessage).foregroundStyle(.red)
                        }
                    }
                }
            }
            .navigationTitle("dropin.request")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(LocalizedStringKey(sent ? "common.close" : "common.cancel")) { dismiss() }
                }
                if !sent {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("suggest.send") {
                            Task { await send() }
                        }
                        .disabled(isSending || message.count > 1000)
                    }
                }
            }
        }
    }

    @MainActor
    private func send() async {
        isSending = true
        defer { isSending = false }
        let draft = DropInDraft(gymId: gym.id, preferredDate: hasDate ? date : nil,
                                preferredClass: preferredClass,
                                message: message.trimmingCharacters(in: .whitespacesAndNewlines))
        do {
            try await services.contributions.submitDropIn(draft)
            sent = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct MyRequestsView: View {
    @Environment(AppServices.self) private var services
    @State private var requests: [DropInRequest] = []
    @State private var isLoading = true

    var body: some View {
        List(requests) { request in
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(request.gymName).font(.headline)
                    Spacer()
                    Text(LocalizedStringKey(request.status.localizedKey))
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.secondary.opacity(0.15)))
                }
                if let date = request.preferredDate {
                    Text(BGDate.string(date, date: .medium, time: .none))
                        .font(.subheadline)
                }
                if let preferredClass = request.preferredClass, !preferredClass.isEmpty {
                    Text(preferredClass).font(.subheadline).foregroundStyle(.secondary)
                }
                if !request.message.isEmpty {
                    Text(request.message).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .overlay {
            if !isLoading && requests.isEmpty {
                ContentUnavailableView("dropin.none", systemImage: "tray")
            }
        }
        .navigationTitle("dropin.myRequests")
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
        requests = (try? await services.contributions.myDropInRequests()) ?? []
    }
}
