import SwiftUI

/// Competition record (W-L, submission %, medals). Synced data comes from Smoothcomp; manual medals are "unverified".
struct AthleteRecordCard: View {
    @Environment(AppServices.self) private var services
    let userId: UUID
    var smoothcompURL: URL?
    var isMe: Bool = false

    @State private var record: AthleteRecord?
    @State private var medals: [AthleteMedal] = []
    @State private var showAddMedal = false
    @State private var syncMessage: String?
    @State private var isSyncing = false
    @State private var showAll = false

    private var counts: MedalCounts { MedalCounts(medals) }
    private var visibleMedals: [AthleteMedal] { showAll ? medals : Array(medals.prefix(5)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("athlete.record", systemImage: "trophy")
                    .font(.headline)
                Spacer()
                if let smoothcompURL {
                    Link(destination: smoothcompURL) {
                        Label("athlete.smoothcomp.open", systemImage: "arrow.up.right.square")
                            .font(.caption)
                    }
                }
            }

            HStack(spacing: 0) {
                stat(value: record.map { "\($0.wins)-\($0.losses)" } ?? "–", label: "athlete.wl")
                stat(value: record.map { "\($0.submissionPercent)%" } ?? "–", label: "athlete.subPercent")
                medalStat(count: counts.gold, color: Color.yellow)
                medalStat(count: counts.silver, color: Color.gray)
                medalStat(count: counts.bronze, color: Color.orange)
            }

            if medals.isEmpty {
                Text("athlete.noMedals")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(visibleMedals) { medal in
                medalRow(medal)
            }
            if medals.count > 5 {
                Button(showAll ? LocalizedStringKey("athlete.showLess") : LocalizedStringKey("athlete.showAll")) {
                    showAll.toggle()
                }
                .font(.caption)
                .buttonStyle(.borderless)
            }

            if isMe {
                HStack {
                    Button {
                        showAddMedal = true
                    } label: {
                        Label("athlete.addMedal", systemImage: "plus")
                    }
                    Spacer()
                    if smoothcompURL != nil {
                        Button {
                            Task { await sync() }
                        } label: {
                            if isSyncing {
                                ProgressView()
                            } else {
                                Label("athlete.sync", systemImage: "arrow.triangle.2.circlepath")
                            }
                        }
                        .disabled(isSyncing)
                    }
                }
                .font(.subheadline)
                .buttonStyle(.borderless)
                if let syncMessage {
                    Text(syncMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.secondary.opacity(0.08)))
        .task(id: userId) {
            await load()
        }
        .sheet(isPresented: $showAddMedal) {
            AddMedalView {
                Task { await load() }
            }
        }
    }

    private func stat(value: String, label: LocalizedStringKey) -> some View {
        VStack(spacing: 2) {
            Text(verbatim: value).font(.headline)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func medalStat(count: Int, color: Color) -> some View {
        VStack(spacing: 2) {
            Image(systemName: "medal.fill").foregroundStyle(color)
            Text(verbatim: "\(count)").font(.headline)
        }
        .frame(maxWidth: .infinity)
    }

    private func medalRow(_ medal: AthleteMedal) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "medal.fill")
                .foregroundStyle(medal.placement == 1 ? Color.yellow : (medal.placement == 2 ? Color.gray : Color.orange))
            VStack(alignment: .leading, spacing: 2) {
                Text(medal.eventName).font(.subheadline)
                HStack(spacing: 6) {
                    Text(LocalizedStringKey(medal.localizedPlacementKey))
                    if let division = medal.division {
                        Text(verbatim: "· \(division)")
                    }
                    if let date = medal.eventDate {
                        Text(verbatim: "· \(BGDate.string(date, date: .medium, time: .none))")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if !medal.verified {
                Text("athlete.unverified")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.orange.opacity(0.18)))
            }
            if isMe && medal.source == .manual {
                Button {
                    Task { await delete(medal) }
                } label: {
                    Image(systemName: "trash").font(.caption)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("athlete.deleteMedal"))
            }
        }
    }

    @MainActor
    private func load() async {
        record = try? await services.athletes.record(userId: userId)
        medals = (try? await services.athletes.medals(userId: userId)) ?? []
    }

    @MainActor
    private func delete(_ medal: AthleteMedal) async {
        try? await services.athletes.deleteMedal(id: medal.id)
        medals.removeAll { $0.id == medal.id }
    }

    @MainActor
    private func sync() async {
        isSyncing = true
        defer { isSyncing = false }
        do {
            let raw = try await services.athletes.syncSmoothcomp()
            let status = SmoothcompSyncStatus(rawValue: raw) ?? .error
            syncMessage = String(localized: String.LocalizationValue(status.localizedKey))
            await load()
        } catch {
            syncMessage = error.localizedDescription
        }
    }
}

struct AddMedalView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    let onSaved: () -> Void
    @State private var eventName = ""
    @State private var placement = 1
    @State private var division = ""
    @State private var hasDate = false
    @State private var date = Date()
    @State private var errorMessage: String?
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("athlete.medal.event", text: $eventName)
                    Picker("athlete.medal.placement", selection: $placement) {
                        Text("medal.gold").tag(1)
                        Text("medal.silver").tag(2)
                        Text("medal.bronze").tag(3)
                    }
                    TextField("athlete.medal.division", text: $division)
                    Toggle("athlete.medal.hasDate", isOn: $hasDate)
                    if hasDate {
                        DatePicker("athlete.medal.date", selection: $date, in: ...Date(), displayedComponents: .date)
                    }
                } footer: {
                    Text("athlete.medal.footer")
                }
                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("athlete.addMedal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.save") {
                        Task { await save() }
                    }
                    .disabled(eventName.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
        }
    }

    @MainActor
    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let draft = MedalDraft(eventName: eventName.trimmingCharacters(in: .whitespaces), placement: placement,
                               division: division.trimmingCharacters(in: .whitespaces),
                               eventDate: hasDate ? date : nil)
        do {
            try await services.athletes.addMedal(draft)
            onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
