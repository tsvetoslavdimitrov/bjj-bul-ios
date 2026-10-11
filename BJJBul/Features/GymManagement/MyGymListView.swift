import SwiftUI

/// Profile → My gym: gyms I belong to, join with an invite code, claim a gym.
struct MyGymListView: View {
    @Environment(AppServices.self) private var services
    @State private var gyms: [MyGym] = []
    @State private var isLoading = true
    @State private var code = ""
    @State private var message: String?
    @State private var showClaim = false

    var body: some View {
        List {
            Section {
                if gyms.isEmpty && !isLoading {
                    Text("gym.my.none").foregroundStyle(.secondary)
                }
                ForEach(gyms) { gym in
                    if gym.role.isStaff && gym.status == .active {
                        NavigationLink {
                            GymDashboardView(myGym: gym)
                        } label: {
                            row(gym)
                        }
                    } else if gym.status == .active {
                        NavigationLink {
                            StudentGymView(myGym: gym)
                        } label: {
                            row(gym)
                        }
                    } else {
                        row(gym)
                    }
                }
            } header: {
                Text("gym.my")
            }

            Section {
                HStack {
                    TextField("gym.invite.code", text: $code)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    Button("gym.invite.join") {
                        Task { await redeem() }
                    }
                    .disabled(code.trimmingCharacters(in: .whitespaces).count < 4)
                }
            } header: {
                Text("gym.invite.haveCode")
            } footer: {
                Text("gym.invite.footer")
            }

            Section {
                Button {
                    showClaim = true
                } label: {
                    Label("gym.claim", systemImage: "checkmark.shield")
                }
            } footer: {
                Text("gym.claim.footer")
            }

            if let message {
                Section {
                    Text(message).font(.footnote)
                }
            }
        }
        .navigationTitle("gym.my")
        .sheet(isPresented: $showClaim) {
            ClaimGymView(preselectedGymId: nil)
        }
        .refreshable { await load() }
        .task { await load() }
    }

    private func row(_ gym: MyGym) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(gym.name).font(.headline)
            HStack(spacing: 6) {
                Text(LocalizedStringKey(gym.role.localizedKey))
                Text(verbatim: "·")
                Text(LocalizedStringKey(gym.status.localizedKey))
                if gym.role.isStaff && !gym.hasAccess {
                    Text(verbatim: "·")
                    Text("subscription.inactive").foregroundStyle(.red)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    @MainActor
    private func load() async {
        defer { isLoading = false }
        gyms = (try? await services.gymManagement.myGyms()) ?? []
    }

    @MainActor
    private func redeem() async {
        do {
            _ = try await services.gymManagement.redeemInvite(code: code)
            code = ""
            message = String(localized: "gym.invite.joined")
            await load()
        } catch {
            message = String(localized: "gym.invite.invalid")
        }
    }
}

/// Claim request (owner or coach), reviewed by an admin.
struct ClaimGymView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    let preselectedGymId: UUID?
    @State private var gyms: [Gym] = []
    @State private var gymId: UUID?
    @State private var role: GymRole = .owner
    @State private var message = ""
    @State private var contact = ""
    @State private var sent = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                if sent {
                    Section {
                        Label("gym.claim.sent", systemImage: "checkmark.circle").foregroundStyle(.green)
                    }
                } else {
                    Section {
                        Picker("openmat.gym", selection: $gymId) {
                            Text("openmat.gym.choose").tag(UUID?.none)
                            ForEach(gyms) { gym in
                                Text(gym.name).tag(UUID?.some(gym.id))
                            }
                        }
                        .pickerStyle(.navigationLink)
                        Picker("gym.claim.role", selection: $role) {
                            Text("gymrole.owner").tag(GymRole.owner)
                            Text("gymrole.coach").tag(GymRole.coach)
                        }
                        TextField("gym.claim.contact", text: $contact)
                    }
                    Section {
                        TextEditor(text: $message).frame(minHeight: 100)
                    } header: {
                        Text("gym.claim.message")
                    } footer: {
                        Text("gym.claim.trial")
                    }
                    if let errorMessage {
                        Section { Text(errorMessage).foregroundStyle(.red) }
                    }
                }
            }
            .navigationTitle("gym.claim")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(LocalizedStringKey(sent ? "common.close" : "common.cancel")) { dismiss() }
                }
                if !sent {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("contribute.submit") {
                            Task { await submit() }
                        }
                        .disabled(gymId == nil || message.count > 1000)
                    }
                }
            }
            .task {
                gyms = ((try? await services.gyms.gyms(cityId: nil)) ?? []).sorted { $0.name < $1.name }
                if gymId == nil { gymId = preselectedGymId }
            }
        }
    }

    @MainActor
    private func submit() async {
        guard let gymId else { return }
        do {
            try await services.gymManagement.claimGym(GymClaimDraft(gymId: gymId, role: role,
                                                                    message: message, contact: contact))
            sent = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Student view of a gym: today's classes with self check-in.
struct StudentGymView: View {
    @Environment(AppServices.self) private var services
    let myGym: MyGym
    @State private var classes: [ClassSchedule] = []
    @State private var checkedIn: Set<UUID> = []
    @State private var errorMessage: String?

    private var todayWeekday: Int { GymDates.isoWeekday(Date()) }

    var body: some View {
        List {
            Section {
                if classes.isEmpty {
                    Text("gym.today.none").foregroundStyle(.secondary)
                }
                ForEach(classes) { item in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(verbatim: "\(item.startTime)–\(item.endTime)").font(.headline)
                            Text(LocalizedStringKey("class.\(item.type.rawValue)")).font(.caption)
                        }
                        Spacer()
                        if checkedIn.contains(item.id) {
                            Label("gym.checkedIn", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        } else {
                            Button("gym.checkIn") {
                                Task { await checkIn(item) }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!myGym.hasAccess)
                        }
                    }
                }
            } header: {
                Text("gym.today")
            }
            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red) }
            }
        }
        .navigationTitle(myGym.name)
        .task { await load() }
    }

    @MainActor
    private func load() async {
        let all = (try? await services.gyms.schedule(gymId: myGym.gymId)) ?? []
        classes = all.filter { $0.weekday == todayWeekday }.sorted { $0.startTime < $1.startTime }
        guard let uid = services.currentUser?.id else { return }
        var set: Set<UUID> = []
        for item in classes {
            let ids = (try? await services.gymManagement.attendance(gymId: myGym.gymId, classId: item.id, date: Date())) ?? []
            if ids.contains(uid) { set.insert(item.id) }
        }
        checkedIn = set
    }

    @MainActor
    private func checkIn(_ item: ClassSchedule) async {
        guard let uid = services.currentUser?.id else { return }
        do {
            try await services.gymManagement.checkIn(gymId: myGym.gymId, classId: item.id, userId: uid, date: Date())
            checkedIn.insert(item.id)
        } catch {
            let text = String(describing: error)
            errorMessage = text.contains("no_credits") ? String(localized: "pass.noCredits") : error.localizedDescription
        }
    }
}

enum GymDates {
    /// 1 = Monday ... 7 = Sunday, in Bulgarian time.
    static func isoWeekday(_ date: Date) -> Int {
        let weekday = Calendar.bulgaria.component(.weekday, from: date) // 1 = Sunday
        return weekday == 1 ? 7 : weekday - 1
    }
}
