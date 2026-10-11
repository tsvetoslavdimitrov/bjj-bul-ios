import SwiftUI

struct OpenMatsListContent: View {
    @Environment(AppServices.self) private var services
    @State private var openMats: [OpenMat] = []
    @State private var cities: [City] = []
    @State private var cityFilter: UUID?
    @State private var styleFilter: OpenMatStyle?
    @State private var onlyVerified = false
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showComposer = false
    @State private var showSignInHint = false
    @State private var calendarMessage: String?

    private var filtered: [OpenMat] {
        openMats.filter { item in
            (cityFilter == nil || item.cityId == cityFilter)
                && (styleFilter == nil || item.style == styleFilter || item.style == .both)
                && (!onlyVerified || item.verified)
        }
    }

    private var sections: [(key: Date, items: [OpenMat])] {
        let calendar = Calendar.bulgaria
        var result: [(key: Date, items: [OpenMat])] = []
        for item in filtered.sorted(by: { $0.startsAt < $1.startsAt }) {
            let day = calendar.startOfDay(for: item.startsAt)
            if let index = result.firstIndex(where: { $0.key == day }) {
                result[index].items.append(item)
            } else {
                result.append((key: day, items: [item]))
            }
        }
        return result
    }

    var body: some View {
        List {
            ForEach(sections, id: \.key) { section in
                Section(BGDate.dayTitle(section.key)) {
                    ForEach(section.items) { item in
                        row(item)
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
                Text("openmat.footer")
            }
        }
        .overlay {
            if isLoading && openMats.isEmpty {
                ProgressView()
            } else if filtered.isEmpty && errorMessage == nil {
                ContentUnavailableView("openmat.empty", systemImage: "calendar")
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                filterMenu
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    if services.isSignedIn {
                        showComposer = true
                    } else {
                        showSignInHint = true
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(Text("openmat.add"))
            }
        }
        .sheet(isPresented: $showComposer) {
            OpenMatComposerView {
                Task { await load() }
            }
        }
        .alert("contribute.signInRequired", isPresented: $showSignInHint) {
            Button("common.close", role: .cancel) {}
        }
        .alert(calendarMessage ?? "", isPresented: Binding(
            get: { calendarMessage != nil },
            set: { if !$0 { calendarMessage = nil } }
        )) {
            Button("common.close", role: .cancel) {}
        }
        .refreshable {
            await load()
        }
        .task {
            await load()
        }
    }

    private var filterMenu: some View {
        Menu {
            Picker("openmat.filter.city", selection: $cityFilter) {
                Text("coaches.filter.all").tag(UUID?.none)
                ForEach(cities) { city in
                    Text(city.localizedName).tag(UUID?.some(city.id))
                }
            }
            Picker("openmat.filter.style", selection: $styleFilter) {
                Text("coaches.filter.all").tag(OpenMatStyle?.none)
                Text("openmat.style.gi").tag(OpenMatStyle?.some(.gi))
                Text("openmat.style.nogi").tag(OpenMatStyle?.some(.nogi))
            }
            Toggle("openmat.filter.verified", isOn: $onlyVerified)
        } label: {
            Image(systemName: cityFilter == nil && styleFilter == nil && !onlyVerified
                  ? "line.3.horizontal.decrease.circle"
                  : "line.3.horizontal.decrease.circle.fill")
        }
    }

    private func row(_ item: OpenMat) -> some View {
        let isMine = item.postedBy != nil && item.postedBy == services.currentUser?.id
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(item.gymName).font(.headline)
                Spacer()
                if item.verified {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                        .accessibilityLabel(Text("openmat.verified"))
                } else {
                    Text("openmat.unverified")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 8) {
                Label("\(BGDate.time(item.startsAt))–\(BGDate.time(item.endsAt))", systemImage: "clock")
                Text(LocalizedStringKey(item.style.localizedKey))
                if let fee = item.fee {
                    if fee == 0 {
                        Text("openmat.free")
                    } else {
                        Text(verbatim: "\(String(format: "%.0f", fee)) \(item.currency)")
                    }
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            if !item.notes.isEmpty {
                Text(item.notes).font(.footnote)
            }
            HStack {
                Button {
                    Task { await addToCalendar(item) }
                } label: {
                    Label("events.addToCalendar", systemImage: "calendar.badge.plus")
                }
                .buttonStyle(.borderless)
                .font(.caption)
                Spacer()
                if isMine {
                    Button(role: .destructive) {
                        Task { await delete(item) }
                    } label: {
                        Label("post.delete", systemImage: "trash")
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
            }
        }
        .padding(.vertical, 2)
    }

    @MainActor
    private func load() async {
        defer { isLoading = false }
        if cities.isEmpty {
            cities = (try? await services.gyms.cities()) ?? []
        }
        do {
            openMats = try await services.openMats.upcomingOpenMats()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func delete(_ item: OpenMat) async {
        do {
            try await services.openMats.deleteOpenMat(id: item.id)
            openMats.removeAll { $0.id == item.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func addToCalendar(_ item: OpenMat) async {
        switch await CalendarService.add(item) {
        case .added:
            calendarMessage = String(localized: "events.calendar.added")
        case .denied:
            calendarMessage = String(localized: "events.calendar.denied")
        case .failed(let message):
            calendarMessage = message
        }
    }
}

struct OpenMatComposerView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    let onSaved: () -> Void

    @State private var gyms: [Gym] = []
    @State private var gymId: UUID?
    @State private var startsAt = Calendar.bulgaria.date(byAdding: .day, value: 1, to: Date()) ?? Date()
    @State private var durationMinutes = 120
    @State private var style: OpenMatStyle = .both
    @State private var feeText = ""
    @State private var notes = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("openmat.gym", selection: $gymId) {
                        Text("openmat.gym.choose").tag(UUID?.none)
                        ForEach(gyms) { gym in
                            Text(gym.name).tag(UUID?.some(gym.id))
                        }
                    }
                    DatePicker("openmat.start", selection: $startsAt, in: Date()...)
                    Stepper(value: $durationMinutes, in: 30...360, step: 30) {
                        Text("openmat.duration \(durationMinutes)")
                    }
                    Picker("openmat.style", selection: $style) {
                        ForEach(OpenMatStyle.allCases, id: \.self) { item in
                            Text(LocalizedStringKey(item.localizedKey)).tag(item)
                        }
                    }
                    TextField("openmat.fee", text: $feeText)
                        .keyboardType(.decimalPad)
                }
                Section("openmat.notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 80)
                } footer: {
                    Text("openmat.verifyNote")
                }
                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("openmat.add")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.save") {
                        Task { await save() }
                    }
                    .disabled(gymId == nil || isSaving || notes.count > 1000)
                }
            }
            .task {
                let list = (try? await services.gyms.gyms(cityId: nil)) ?? []
                gyms = list.sorted { $0.name < $1.name }
                if gymId == nil, let home = services.currentUser?.homeGymId {
                    gymId = home
                }
            }
        }
    }

    @MainActor
    private func save() async {
        guard let gymId else { return }
        isSaving = true
        defer { isSaving = false }
        let fee = Double(feeText.replacingOccurrences(of: ",", with: "."))
        let draft = OpenMatDraft(gymId: gymId, startsAt: startsAt,
                                 endsAt: startsAt.addingTimeInterval(Double(durationMinutes) * 60),
                                 style: style, fee: fee,
                                 notes: notes.trimmingCharacters(in: .whitespacesAndNewlines))
        do {
            try await services.openMats.createOpenMat(draft)
            onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
