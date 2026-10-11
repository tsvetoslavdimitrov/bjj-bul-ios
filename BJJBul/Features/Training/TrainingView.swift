import SwiftUI
import Charts

struct TrainingView: View {
    @Environment(AppServices.self) private var services
    @State private var sessions: [TrainingSession] = []
    @State private var gyms: [Gym] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var editing: TrainingSession?

    private var weeks: [WeekBucket] { TrainingStats.weeks(sessions) }
    private var thisWeek: WeekBucket? { weeks.last }

    var body: some View {
        NavigationStack {
            Group {
                if services.isSignedIn {
                    content
                } else {
                    ContentUnavailableView {
                        Label("training.title", systemImage: "figure.martial.arts")
                    } description: {
                        Text("training.signIn")
                    }
                }
            }
            .navigationTitle("training.title")
            .toolbar {
                if services.isSignedIn {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            editing = TrainingSession.new()
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel(Text("training.add"))
                    }
                }
            }
            .sheet(item: $editing) { session in
                TrainingEditorView(session: session, gyms: gyms,
                                   isNew: !sessions.contains { $0.id == session.id }) {
                    Task { await load() }
                }
            }
            .task(id: services.isSignedIn) {
                await load()
            }
        }
    }

    private var content: some View {
        List {
            Section("training.thisWeek") {
                HStack {
                    statTile(value: "\(thisWeek?.sessions ?? 0)", label: "training.stat.sessions")
                    statTile(value: String(format: "%.1f", thisWeek?.hours ?? 0), label: "training.stat.hours")
                    statTile(value: "\(thisWeek?.rounds ?? 0)", label: "training.stat.rounds")
                    statTile(value: "\(TrainingStats.weekStreak(sessions))", label: "training.stat.streak")
                }
            }
            Section("training.chart") {
                Chart(weeks) { week in
                    BarMark(
                        x: .value("Week", BGDate.shortDay(week.weekStart)),
                        y: .value("Hours", week.hours)
                    )
                    .foregroundStyle(Color.accentColor)
                }
                .frame(height: 160)
            }
            Section("training.sessions") {
                if sessions.isEmpty && !isLoading {
                    Text("training.empty").foregroundStyle(.secondary)
                }
                ForEach(sessions) { session in
                    Button {
                        editing = session
                    } label: {
                        sessionRow(session)
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { offsets in
                    let targets = offsets.map { sessions[$0] }
                    Task { await delete(targets) }
                }
            }
            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            Section {
            } footer: {
                Text("training.private")
            }
        }
        .refreshable {
            await load()
        }
    }

    private func statTile(value: String, label: LocalizedStringKey) -> some View {
        VStack(spacing: 2) {
            Text(verbatim: value).font(.title3).bold()
            Text(label).font(.caption2).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private func sessionRow(_ session: TrainingSession) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(BGDate.string(session.date, date: .medium, time: .none)).font(.headline)
                Spacer()
                Text(LocalizedStringKey(session.type.localizedKey))
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.secondary.opacity(0.15)))
            }
            HStack(spacing: 12) {
                Label("\(session.durationMinutes) min", systemImage: "clock")
                if session.sparringRounds > 0 {
                    Label("\(session.sparringRounds)", systemImage: "figure.wrestling")
                }
                if let rating = session.rating {
                    RatingStarsView(rating: Double(rating))
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            if let gymId = session.gymId, let gym = gyms.first(where: { $0.id == gymId }) {
                Text(gym.name).font(.caption).foregroundStyle(.secondary)
            }
            if !session.techniques.isEmpty {
                Text(session.techniques.map { "#\($0)" }.joined(separator: " "))
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
            }
        }
        .contentShape(Rectangle())
    }

    @MainActor
    private func load() async {
        defer { isLoading = false }
        guard services.isSignedIn else {
            sessions = []
            return
        }
        if gyms.isEmpty {
            gyms = ((try? await services.gyms.gyms(cityId: nil)) ?? []).sorted { $0.name < $1.name }
        }
        do {
            sessions = try await services.training.sessions().sorted { $0.date > $1.date }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func delete(_ targets: [TrainingSession]) async {
        for target in targets {
            do {
                try await services.training.delete(id: target.id)
                sessions.removeAll { $0.id == target.id }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

struct TrainingEditorView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    let gyms: [Gym]
    let isNew: Bool
    let onSaved: () -> Void
    @State private var session: TrainingSession
    @State private var techniqueText = ""
    @State private var hasRating: Bool
    @State private var ratingValue: Int
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(session: TrainingSession, gyms: [Gym], isNew: Bool, onSaved: @escaping () -> Void) {
        self.gyms = gyms
        self.isNew = isNew
        self.onSaved = onSaved
        _session = State(initialValue: session)
        _hasRating = State(initialValue: session.rating != nil)
        _ratingValue = State(initialValue: session.rating ?? 3)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("training.date", selection: $session.date, in: ...Date(), displayedComponents: .date)
                    Stepper(value: $session.durationMinutes, in: 15...600, step: 15) {
                        Text("training.duration \(session.durationMinutes)")
                    }
                    Picker("training.type", selection: $session.type) {
                        ForEach(TrainingType.allCases, id: \.self) { type in
                            Text(LocalizedStringKey(type.localizedKey)).tag(type)
                        }
                    }
                    Picker("training.gym", selection: $session.gymId) {
                        Text("training.gym.none").tag(UUID?.none)
                        ForEach(gyms) { gym in
                            Text(gym.name).tag(UUID?.some(gym.id))
                        }
                    }
                    Stepper(value: $session.sparringRounds, in: 0...100) {
                        Text("training.rounds \(session.sparringRounds)")
                    }
                }
                Section("training.techniques") {
                    HStack {
                        TextField("training.technique.add", text: $techniqueText)
                            .onSubmit(addTechnique)
                        Button(action: addTechnique) {
                            Image(systemName: "plus.circle.fill")
                        }
                        .disabled(techniqueText.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    ForEach(session.techniques, id: \.self) { technique in
                        Text(verbatim: "#\(technique)")
                    }
                    .onDelete { offsets in
                        session.techniques.remove(atOffsets: offsets)
                    }
                }
                Section("training.rating") {
                    Toggle("training.rate", isOn: $hasRating)
                    if hasRating {
                        StarPicker(rating: $ratingValue)
                    }
                }
                Section("training.notes") {
                    TextEditor(text: $session.notes)
                        .frame(minHeight: 100)
                }
                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(isNew ? LocalizedStringKey("training.add") : LocalizedStringKey("training.edit"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.save") {
                        Task { await save() }
                    }
                    .disabled(isSaving || session.notes.count > 4000)
                }
            }
        }
    }

    private func addTechnique() {
        let value = techniqueText.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "#", with: "")
        guard !value.isEmpty, !session.techniques.contains(value) else { return }
        session.techniques.append(value)
        techniqueText = ""
    }

    @MainActor
    private func save() async {
        isSaving = true
        defer { isSaving = false }
        addTechnique()
        var toSave = session
        toSave.rating = hasRating ? max(1, ratingValue) : nil
        do {
            try await services.training.save(toSave)
            onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
