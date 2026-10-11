import SwiftUI

/// "My gym" dashboard for owners and coaches.
struct GymDashboardView: View {
    @Environment(AppServices.self) private var services
    let myGym: MyGym
    @State private var roster: [RosterMember] = []
    @State private var payments: [PaymentStatusRow] = []
    @State private var classes: [ClassSchedule] = []
    @State private var subscription: GymSubscription?
    @State private var gym: Gym?

    private var hasAccess: Bool { subscription?.hasAccess ?? myGym.hasAccess }
    private var students: [RosterMember] { roster.filter { $0.role == .student && $0.status == .active } }
    private var pending: [RosterMember] { roster.filter { $0.status == .pending } }
    private var overdue: Int { payments.filter { !$0.paid }.count }
    private var todayClasses: [ClassSchedule] {
        classes.filter { $0.weekday == GymDates.isoWeekday(Date()) }.sorted { $0.startTime < $1.startTime }
    }

    var body: some View {
        List {
            if !hasAccess {
                Section {
                    NavigationLink {
                        SubscriptionView(myGym: myGym)
                    } label: {
                        Label("subscription.inactive.banner", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
            }

            Section {
                HStack {
                    tile("\(students.count)", "gym.dash.students")
                    tile("\(pending.count)", "gym.dash.pending")
                    tile("\(overdue)", "gym.dash.overdue")
                }
                if todayClasses.isEmpty {
                    Text("gym.today.none").foregroundStyle(.secondary)
                }
                ForEach(todayClasses) { item in
                    NavigationLink {
                        AttendanceView(myGym: myGym, item: item, roster: roster)
                    } label: {
                        HStack {
                            Text(verbatim: "\(item.startTime)–\(item.endTime)").font(.headline)
                            Text(LocalizedStringKey("class.\(item.type.rawValue)"))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(!hasAccess)
                }
            } header: {
                Text("gym.dash.overview")
            }

            Section {
                NavigationLink {
                    StudentsManageView(myGym: myGym, canManage: hasAccess)
                } label: {
                    Label("gym.dash.studentsSection", systemImage: "person.3")
                }
                NavigationLink {
                    CoachesManageView(myGym: myGym, canManage: hasAccess)
                } label: {
                    Label("gym.dash.coaches", systemImage: "person.badge.shield.checkmark")
                }
                NavigationLink {
                    ClassesManageView(myGym: myGym, canManage: hasAccess)
                } label: {
                    Label("gym.dash.classes", systemImage: "calendar")
                }
                NavigationLink {
                    ReportsView(myGym: myGym)
                } label: {
                    Label("reports.title", systemImage: "chart.bar.xaxis")
                }
                NavigationLink {
                    KioskSetupView(myGym: myGym)
                } label: {
                    Label("kiosk.title", systemImage: "ipad.landscape")
                }
                NavigationLink {
                    KioskAttendanceView(myGym: myGym)
                } label: {
                    Label("kiosk.attendance", systemImage: "list.bullet.clipboard")
                }
                NavigationLink {
                    PaymentsManageView(myGym: myGym, canManage: hasAccess)
                } label: {
                    Label("gym.dash.payments", systemImage: "eurosign.circle")
                }
                if let gym {
                    NavigationLink {
                        GymSettingsView(myGym: myGym, gym: gym, canManage: hasAccess)
                    } label: {
                        Label("gym.dash.settings", systemImage: "gearshape")
                    }
                }
                if myGym.role == .owner {
                    NavigationLink {
                        SubscriptionView(myGym: myGym)
                    } label: {
                        Label("subscription.title", systemImage: "creditcard")
                    }
                }
            }
        }
        .navigationTitle(myGym.name)
        .refreshable { await load() }
        .task { await load() }
    }

    private func tile(_ value: String, _ label: LocalizedStringKey) -> some View {
        VStack(spacing: 2) {
            Text(verbatim: value).font(.title3).bold()
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    @MainActor
    private func load() async {
        let service = services.gymManagement
        subscription = try? await service.subscription(gymId: myGym.gymId)
        roster = (try? await service.roster(gymId: myGym.gymId)) ?? []
        payments = (try? await service.paymentStatus(gymId: myGym.gymId)) ?? []
        classes = (try? await services.gyms.schedule(gymId: myGym.gymId)) ?? []
        gym = try? await services.gyms.gym(id: myGym.gymId)
    }
}

// MARK: - Students

struct StudentsManageView: View {
    @Environment(AppServices.self) private var services
    let myGym: MyGym
    let canManage: Bool
    @State private var roster: [RosterMember] = []
    @State private var memberships: [Membership] = []
    @State private var promoting: RosterMember?
    @State private var inviteCode: String?
    @State private var errorMessage: String?

    private var pending: [RosterMember] { roster.filter { $0.role == .student && $0.status == .pending } }
    private var active: [RosterMember] { roster.filter { $0.role == .student && $0.status == .active } }

    var body: some View {
        List {
            if !pending.isEmpty {
                Section {
                    ForEach(pending) { member in
                        HStack {
                            Text(member.displayName.isEmpty ? String(localized: "feed.anonymous") : member.displayName)
                            Spacer()
                            Button("gym.approve") {
                                Task { await setStatus(member, .active) }
                            }
                            .buttonStyle(.borderedProminent)
                            Button("gym.decline", role: .destructive) {
                                Task { await setStatus(member, .removed) }
                            }
                            .buttonStyle(.bordered)
                        }
                        .disabled(!canManage)
                    }
                } header: {
                    Text("gym.pendingRequests")
                }
            }

            Section {
                if active.isEmpty {
                    Text("gym.students.none").foregroundStyle(.secondary)
                }
                ForEach(active) { member in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(member.displayName.isEmpty ? String(localized: "feed.anonymous") : member.displayName)
                                .font(.headline)
                            Spacer()
                            Text(LocalizedStringKey(member.belt.localizedKey)).font(.caption)
                            Text("profile.stripes \(member.stripes)").font(.caption).foregroundStyle(.secondary)
                        }
                        if !memberships.isEmpty {
                            Picker("gym.membership", selection: Binding(
                                get: { member.membershipId },
                                set: { newValue in Task { await setMembership(member, newValue) } }
                            )) {
                                Text("gym.membership.none").tag(UUID?.none)
                                ForEach(memberships) { plan in
                                    Text(plan.name).tag(UUID?.some(plan.id))
                                }
                            }
                            .font(.caption)
                        }
                    }
                    .swipeActions {
                        if canManage {
                            Button("gym.remove", role: .destructive) {
                                Task { await setStatus(member, .removed) }
                            }
                            Button("gym.promote") {
                                promoting = member
                            }
                            .tint(.purple)
                        }
                    }
                }
            } header: {
                Text("gym.dash.studentsSection")
            } footer: {
                Text("gym.students.footer")
            }

            Section {
                Button {
                    Task { await createInvite() }
                } label: {
                    Label("gym.invite.students", systemImage: "person.badge.plus")
                }
                .disabled(!canManage)
                if let inviteCode {
                    HStack {
                        Text(verbatim: inviteCode).font(.title3.monospaced()).bold()
                        Spacer()
                        ShareLink(item: String(localized: "gym.invite.shareText \(myGym.name) \(inviteCode)"))
                    }
                }
            } footer: {
                Text("gym.invite.studentsFooter")
            }
            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red) }
            }
        }
        .navigationTitle("gym.dash.studentsSection")
        .sheet(item: $promoting) { member in
            PromoteView(myGym: myGym, member: member) {
                Task { await load() }
            }
        }
        .refreshable { await load() }
        .task { await load() }
    }

    @MainActor
    private func load() async {
        roster = (try? await services.gymManagement.roster(gymId: myGym.gymId)) ?? []
        memberships = ((try? await services.gymManagement.memberships(gymId: myGym.gymId)) ?? []).filter { $0.active }
    }

    @MainActor
    private func setStatus(_ member: RosterMember, _ status: MemberStatus) async {
        do {
            try await services.gymManagement.setMemberStatus(memberId: member.memberId, status: status)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func setMembership(_ member: RosterMember, _ membershipId: UUID?) async {
        do {
            try await services.gymManagement.setMemberMembership(memberId: member.memberId, membershipId: membershipId)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func createInvite() async {
        do {
            inviteCode = try await services.gymManagement.createInvite(gymId: myGym.gymId, role: .student, maxUses: 50)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct PromoteView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    let myGym: MyGym
    let member: RosterMember
    let onDone: () -> Void
    @State private var belt: Belt
    @State private var stripes: Int
    @State private var note = ""
    @State private var postToFeed = true
    @State private var errorMessage: String?

    init(myGym: MyGym, member: RosterMember, onDone: @escaping () -> Void) {
        self.myGym = myGym
        self.member = member
        self.onDone = onDone
        _belt = State(initialValue: member.belt)
        _stripes = State(initialValue: min(member.stripes + 1, 4))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(member.displayName).font(.headline)
                    Picker("profile.belt", selection: $belt) {
                        ForEach(Belt.allCases, id: \.self) { item in
                            Text(LocalizedStringKey(item.localizedKey)).tag(item)
                        }
                    }
                    Stepper(value: $stripes, in: 0...4) {
                        Text("profile.stripes \(stripes)")
                    }
                    TextField("gym.promote.note", text: $note)
                    Toggle("gym.promote.post", isOn: $postToFeed)
                } footer: {
                    Text("gym.promote.footer")
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
            }
            .navigationTitle("gym.promote")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.save") {
                        Task { await save() }
                    }
                }
            }
        }
    }

    @MainActor
    private func save() async {
        do {
            try await services.gymManagement.promote(gymId: myGym.gymId, userId: member.userId, belt: belt,
                                                     stripes: stripes, note: note, postToFeed: postToFeed)
            onDone()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Coaches

struct CoachesManageView: View {
    @Environment(AppServices.self) private var services
    let myGym: MyGym
    let canManage: Bool
    @State private var roster: [RosterMember] = []
    @State private var students: [RosterMember] = []
    @State private var inviteCode: String?
    @State private var errorMessage: String?

    private var isOwner: Bool { myGym.role == .owner }

    var body: some View {
        List {
            Section {
                ForEach(roster.filter { $0.role != .student && $0.status == .active }) { member in
                    HStack {
                        Text(member.displayName.isEmpty ? String(localized: "feed.anonymous") : member.displayName)
                        Spacer()
                        Text(LocalizedStringKey(member.role.localizedKey))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .swipeActions {
                        if isOwner && canManage && member.role == .coach {
                            Button("gym.remove", role: .destructive) {
                                Task { await update(member, role: nil, status: .removed) }
                            }
                        }
                    }
                }
            } header: {
                Text("gym.dash.coaches")
            }

            if isOwner {
                Section {
                    Button {
                        Task { await createInvite() }
                    } label: {
                        Label("gym.invite.coach", systemImage: "person.badge.plus")
                    }
                    .disabled(!canManage)
                    if let inviteCode {
                        HStack {
                            Text(verbatim: inviteCode).font(.title3.monospaced()).bold()
                            Spacer()
                            ShareLink(item: String(localized: "gym.invite.shareText \(myGym.name) \(inviteCode)"))
                        }
                    }
                } footer: {
                    Text("gym.invite.coachFooter")
                }
                if !students.isEmpty {
                    Section {
                        ForEach(students) { member in
                            Button {
                                Task { await update(member, role: "coach", status: .active) }
                            } label: {
                                Label(member.displayName.isEmpty ? String(localized: "feed.anonymous") : member.displayName,
                                      systemImage: "arrow.up.circle")
                            }
                            .disabled(!canManage)
                        }
                    } header: {
                        Text("gym.makeCoach")
                    }
                }
            }
            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red) }
            }
        }
        .navigationTitle("gym.dash.coaches")
        .task { await load() }
    }

    @MainActor
    private func load() async {
        let all = (try? await services.gymManagement.roster(gymId: myGym.gymId)) ?? []
        roster = all
        students = all.filter { $0.role == .student && $0.status == .active }
    }

    @MainActor
    private func createInvite() async {
        do {
            inviteCode = try await services.gymManagement.createInvite(gymId: myGym.gymId, role: .coach, maxUses: 1)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Role changes go through the member status/membership API; promoting a student to coach uses an invite-free path.
    @MainActor
    private func update(_ member: RosterMember, role: String?, status: MemberStatus) async {
        do {
            if let role, role == "coach" {
                try await services.gymManagement.setMemberRole(memberId: member.memberId, role: .coach)
            } else {
                try await services.gymManagement.setMemberStatus(memberId: member.memberId, status: status)
            }
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
