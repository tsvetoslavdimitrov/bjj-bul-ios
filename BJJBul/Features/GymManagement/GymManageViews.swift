import SwiftUI
import PhotosUI

// MARK: - Classes

struct ClassesManageView: View {
    @Environment(AppServices.self) private var services
    let myGym: MyGym
    let canManage: Bool
    @State private var classes: [ClassSchedule] = []
    @State private var roster: [RosterMember] = []
    @State private var editing: ClassSchedule?
    @State private var errorMessage: String?

    private var days: [Int] { Array(Set(classes.map { $0.weekday })).sorted() }

    var body: some View {
        List {
            ForEach(days, id: \.self) { day in
                Section {
                    ForEach(classes.filter { $0.weekday == day }.sorted { $0.startTime < $1.startTime }) { item in
                        NavigationLink {
                            AttendanceView(myGym: myGym, item: item, roster: roster)
                        } label: {
                            HStack {
                                Text(verbatim: "\(item.startTime)–\(item.endTime)").font(.headline)
                                Text(LocalizedStringKey("class.\(item.type.rawValue)")).foregroundStyle(.secondary)
                            }
                        }
                        .swipeActions {
                            if canManage {
                                Button("post.delete", role: .destructive) {
                                    Task { await delete(item) }
                                }
                                Button("gym.edit") {
                                    editing = item
                                }
                                .tint(.blue)
                            }
                        }
                    }
                } header: {
                    Text(verbatim: Links.weekdayName(day))
                }
            }
            if classes.isEmpty {
                Text("gym.classes.none").foregroundStyle(.secondary)
            }
            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red) }
            }
        }
        .navigationTitle("gym.dash.classes")
        .toolbar {
            if canManage {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editing = ClassSchedule(id: UUID(), gymId: myGym.gymId, coachId: nil, weekday: 1,
                                                startTime: "18:00", endTime: "19:30", type: .gi, level: .all, notes: nil)
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .sheet(item: $editing) { item in
            ClassEditorView(item: item, isNew: !classes.contains { $0.id == item.id }) {
                Task { await load() }
            }
        }
        .refreshable { await load() }
        .task { await load() }
    }

    @MainActor
    private func load() async {
        classes = (try? await services.gyms.schedule(gymId: myGym.gymId)) ?? []
        roster = (try? await services.gymManagement.roster(gymId: myGym.gymId)) ?? []
    }

    @MainActor
    private func delete(_ item: ClassSchedule) async {
        do {
            try await services.gymManagement.deleteClass(id: item.id)
            classes.removeAll { $0.id == item.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct ClassEditorView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    let isNew: Bool
    let onSaved: () -> Void
    @State private var item: ClassSchedule
    @State private var start: Date
    @State private var end: Date
    @State private var errorMessage: String?

    init(item: ClassSchedule, isNew: Bool, onSaved: @escaping () -> Void) {
        self.isNew = isNew
        self.onSaved = onSaved
        _item = State(initialValue: item)
        _start = State(initialValue: ClassEditorView.date(from: item.startTime))
        _end = State(initialValue: ClassEditorView.date(from: item.endTime))
    }

    static func date(from hhmm: String) -> Date {
        let parts = hhmm.split(separator: ":").compactMap { Int($0) }
        var comps = DateComponents()
        comps.hour = parts.first ?? 18
        comps.minute = parts.count > 1 ? parts[1] : 0
        return Calendar.current.date(from: comps) ?? Date()
    }

    static func hhmm(_ date: Date) -> String {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", comps.hour ?? 0, comps.minute ?? 0)
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("gym.class.day", selection: $item.weekday) {
                    ForEach(1...7, id: \.self) { day in
                        Text(verbatim: Links.weekdayName(day)).tag(day)
                    }
                }
                DatePicker("gym.class.start", selection: $start, displayedComponents: .hourAndMinute)
                DatePicker("gym.class.end", selection: $end, displayedComponents: .hourAndMinute)
                Picker("training.type", selection: $item.type) {
                    ForEach(ClassType.allCases, id: \.self) { type in
                        Text(LocalizedStringKey("class.\(type.rawValue)")).tag(type)
                    }
                }
                Picker("gym.class.level", selection: $item.level) {
                    Text("gym.level.all").tag(ClassLevel.all)
                    Text("gym.level.beginner").tag(ClassLevel.beginner)
                    Text("gym.level.advanced").tag(ClassLevel.advanced)
                }
                TextField("openmat.notes", text: Binding(get: { item.notes ?? "" }, set: { item.notes = $0 }))
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            .navigationTitle(isNew ? LocalizedStringKey("gym.class.add") : LocalizedStringKey("gym.class.edit"))
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
        item.startTime = ClassEditorView.hhmm(start)
        item.endTime = ClassEditorView.hhmm(end)
        guard item.endTime > item.startTime else {
            errorMessage = String(localized: "gym.class.timeError")
            return
        }
        do {
            try await services.gymManagement.saveClass(item, isNew: isNew)
            onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct AttendanceView: View {
    @Environment(AppServices.self) private var services
    let myGym: MyGym
    let item: ClassSchedule
    let roster: [RosterMember]
    @State private var date = Date()
    @State private var present: Set<UUID> = []
    @State private var errorMessage: String?

    private var people: [RosterMember] { roster.filter { $0.status == .active } }

    var body: some View {
        List {
            Section {
                DatePicker("dropin.date", selection: $date, in: ...Date(), displayedComponents: .date)
                Text("gym.attendance.count \(present.count)")
                    .foregroundStyle(.secondary)
            }
            Section {
                ForEach(people) { member in
                    Button {
                        Task { await toggle(member) }
                    } label: {
                        HStack {
                            Image(systemName: present.contains(member.userId) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(present.contains(member.userId) ? Color.green : Color.secondary)
                            Text(member.displayName.isEmpty ? String(localized: "feed.anonymous") : member.displayName)
                            Spacer()
                            Text(LocalizedStringKey(member.belt.localizedKey))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("gym.attendance")
            }
            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red) }
            }
        }
        .navigationTitle(Text(verbatim: "\(Links.weekdayName(item.weekday)) \(item.startTime)"))
        .task(id: EventDates.string(from: date)) {
            present = (try? await services.gymManagement.attendance(gymId: myGym.gymId, classId: item.id, date: date)) ?? []
        }
    }

    @MainActor
    private func toggle(_ member: RosterMember) async {
        do {
            if present.contains(member.userId) {
                try await services.gymManagement.undoCheckIn(gymId: myGym.gymId, classId: item.id,
                                                             userId: member.userId, date: date)
                present.remove(member.userId)
            } else {
                try await services.gymManagement.checkIn(gymId: myGym.gymId, classId: item.id,
                                                         userId: member.userId, date: date)
                present.insert(member.userId)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Payments

struct PaymentsManageView: View {
    @Environment(AppServices.self) private var services
    let myGym: MyGym
    let canManage: Bool
    @State private var rows: [PaymentStatusRow] = []
    @State private var memberships: [Membership] = []
    @State private var recording: PaymentStatusRow?
    @State private var claims: [PaymentClaim] = []
    @State private var errorMessage: String?

    private var overdue: [PaymentStatusRow] { rows.filter { !$0.paid } }
    private var paid: [PaymentStatusRow] { rows.filter { $0.paid } }

    var body: some View {
        List {
            if !claims.isEmpty {
                Section {
                    ForEach(claims) { claim in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(claim.displayName.isEmpty ? String(localized: "feed.anonymous") : claim.displayName)
                                    .font(.headline)
                                Spacer()
                                if let amount = claim.amount {
                                    Text(verbatim: String(format: "%.2f EUR", amount))
                                }
                            }
                            HStack(spacing: 4) {
                                Text(LocalizedStringKey(claim.method.localizedKey))
                                if let month = claim.periodMonth {
                                    Text(verbatim: "· \(EventDates.monthTitle(month))")
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            if let reference = claim.reference {
                                Text(verbatim: reference).font(.caption.monospaced())
                            }
                            if let note = claim.note, !note.isEmpty {
                                Text(verbatim: note).font(.caption)
                            }
                            if canManage {
                                HStack {
                                    Button("payclaim.confirm") {
                                        Task { await review(claim, confirm: true) }
                                    }
                                    .buttonStyle(.borderedProminent)
                                    Button("payclaim.reject", role: .destructive) {
                                        Task { await review(claim, confirm: false) }
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                        }
                    }
                } header: {
                    Text("payclaim.title")
                } footer: {
                    Text("payclaim.footer")
                }
            }
            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red) }
            }
            Section {
                if overdue.isEmpty {
                    Text("gym.payments.allPaid").foregroundStyle(.secondary)
                }
                ForEach(overdue) { row in
                    paymentRow(row)
                }
            } header: {
                Text("gym.payments.overdue \(EventDates.monthTitle(Date()))")
            }
            Section {
                ForEach(paid) { row in
                    paymentRow(row)
                }
            } header: {
                Text("gym.payments.paid")
            }
            Section {
                NavigationLink {
                    MembershipPlansView(myGym: myGym, canManage: canManage)
                } label: {
                    Label("gym.memberships", systemImage: "list.bullet.rectangle")
                }
            }
        }
        .navigationTitle("gym.dash.payments")
        .sheet(item: $recording) { row in
            RecordPaymentView(myGym: myGym, row: row, memberships: memberships) {
                Task { await load() }
            }
        }
        .refreshable { await load() }
        .task { await load() }
    }

    private func paymentRow(_ row: PaymentStatusRow) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.displayName.isEmpty ? String(localized: "feed.anonymous") : row.displayName)
                    .font(.headline)
                if let name = row.membershipName {
                    Text(verbatim: "\(name)\(row.price.map { " · \(String(format: "%.2f", $0)) EUR" } ?? "")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if row.paid {
                Text(verbatim: String(format: "%.2f EUR", row.paidAmount))
                    .font(.subheadline)
                    .foregroundStyle(.green)
            } else if canManage {
                Button("gym.payments.record") {
                    recording = row
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    @MainActor
    private func load() async {
        rows = (try? await services.gymManagement.paymentStatus(gymId: myGym.gymId)) ?? []
        memberships = (try? await services.gymManagement.memberships(gymId: myGym.gymId)) ?? []
        claims = (try? await services.gymManagement.paymentClaims(gymId: myGym.gymId)) ?? []
    }

    @MainActor
    private func review(_ claim: PaymentClaim, confirm: Bool) async {
        do {
            if confirm {
                try await services.gymManagement.confirmPaymentClaim(id: claim.id)
            } else {
                try await services.gymManagement.rejectPaymentClaim(id: claim.id, note: "")
            }
            errorMessage = nil
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct RecordPaymentView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    let myGym: MyGym
    let row: PaymentStatusRow
    let memberships: [Membership]
    let onSaved: () -> Void
    @State private var amountText: String
    @State private var method: MemberPaymentMethod = .cash
    @State private var note = ""
    @State private var errorMessage: String?

    init(myGym: MyGym, row: PaymentStatusRow, memberships: [Membership], onSaved: @escaping () -> Void) {
        self.myGym = myGym
        self.row = row
        self.memberships = memberships
        self.onSaved = onSaved
        _amountText = State(initialValue: row.price.map { String(format: "%.2f", $0) } ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(row.displayName).font(.headline)
                    TextField("gym.payments.amount", text: $amountText)
                        .keyboardType(.decimalPad)
                    Picker("gym.payments.method", selection: $method) {
                        ForEach(MemberPaymentMethod.allCases, id: \.self) { item in
                            Text(LocalizedStringKey(item.localizedKey)).tag(item)
                        }
                    }
                    TextField("gym.payments.note", text: $note)
                } footer: {
                    Text("gym.payments.footer")
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
            }
            .navigationTitle("gym.payments.record")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.save") {
                        Task { await save() }
                    }
                    .disabled(Double(amountText.replacingOccurrences(of: ",", with: ".")) == nil)
                }
            }
        }
    }

    @MainActor
    private func save() async {
        guard let amount = Double(amountText.replacingOccurrences(of: ",", with: ".")) else { return }
        let membershipId = memberships.first { $0.name == row.membershipName }?.id
        let draft = MemberPaymentDraft(gymId: myGym.gymId, userId: row.userId, membershipId: membershipId,
                                       amount: amount, method: method, note: note)
        do {
            try await services.gymManagement.recordPayment(draft)
            onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct MembershipPlansView: View {
    @Environment(AppServices.self) private var services
    let myGym: MyGym
    let canManage: Bool
    @State private var plans: [Membership] = []
    @State private var editing: Membership?

    var body: some View {
        List {
            ForEach(plans) { plan in
                Button {
                    if canManage { editing = plan }
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(plan.name).font(.headline)
                            Text(LocalizedStringKey(plan.period.localizedKey)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(verbatim: String(format: "%.2f %@", plan.price, plan.currency))
                        if !plan.active {
                            Text("gym.membership.inactive").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            if plans.isEmpty {
                Text("gym.memberships.none").foregroundStyle(.secondary)
            }
        }
        .navigationTitle("gym.memberships")
        .toolbar {
            if canManage {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editing = Membership(id: UUID(), gymId: myGym.gymId, name: "", price: 60, currency: "EUR",
                                             period: .monthly, active: true)
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .sheet(item: $editing) { plan in
            MembershipEditorView(plan: plan, isNew: !plans.contains { $0.id == plan.id }) {
                Task { await load() }
            }
        }
        .task { await load() }
    }

    @MainActor
    private func load() async {
        plans = (try? await services.gymManagement.memberships(gymId: myGym.gymId)) ?? []
    }
}

struct MembershipEditorView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    let isNew: Bool
    let onSaved: () -> Void
    @State private var plan: Membership
    @State private var priceText: String
    @State private var errorMessage: String?

    init(plan: Membership, isNew: Bool, onSaved: @escaping () -> Void) {
        self.isNew = isNew
        self.onSaved = onSaved
        _plan = State(initialValue: plan)
        _priceText = State(initialValue: String(format: "%.2f", plan.price))
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("gym.membership.name", text: $plan.name)
                TextField("gym.membership.price", text: $priceText).keyboardType(.decimalPad)
                Picker("gym.membership.period", selection: $plan.period) {
                    ForEach(MembershipPeriod.allCases, id: \.self) { item in
                        Text(LocalizedStringKey(item.localizedKey)).tag(item)
                    }
                }
                Toggle("gym.membership.active", isOn: $plan.active)
                if !isNew {
                    Button("post.delete", role: .destructive) {
                        Task { await delete() }
                    }
                }
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            .navigationTitle("gym.memberships")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.save") {
                        Task { await save() }
                    }
                    .disabled(plan.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    @MainActor
    private func save() async {
        guard let price = Double(priceText.replacingOccurrences(of: ",", with: ".")) else {
            errorMessage = String(localized: "gym.membership.priceError")
            return
        }
        plan.price = price
        do {
            try await services.gymManagement.saveMembership(plan, isNew: isNew)
            onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func delete() async {
        do {
            try await services.gymManagement.deleteMembership(id: plan.id)
            onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Settings (gym profile)

struct GymSettingsView: View {
    @Environment(AppServices.self) private var services
    let myGym: MyGym
    let canManage: Bool
    @State private var draft: GymProfileDraft
    @State private var dropInText: String
    @State private var monthlyText: String
    @State private var kidsText: String
    @State private var photoItem: PhotosPickerItem?
    @State private var revolutText = ""

    private var revolutValid: Bool {
        let text = revolutText.trimmingCharacters(in: .whitespaces)
        if text.isEmpty { return true }
        return text.range(of: "^https://revolut\\.me/[A-Za-z0-9._-]+/?$", options: .regularExpression) != nil
    }
    @State private var isSaving = false
    @State private var message: String?

    init(myGym: MyGym, gym: Gym, canManage: Bool) {
        self.myGym = myGym
        self.canManage = canManage
        let d = GymProfileDraft(gym: gym)
        _draft = State(initialValue: d)
        _dropInText = State(initialValue: GymSettingsView.text(d.priceDropIn))
        _monthlyText = State(initialValue: GymSettingsView.text(d.priceMonthly))
        _kidsText = State(initialValue: GymSettingsView.text(d.priceKids))
    }

    static func text(_ value: Decimal?) -> String {
        guard let value else { return "" }
        return NSDecimalNumber(decimal: value).stringValue
    }

    static func decimal(_ text: String) -> Decimal? {
        let cleaned = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard !cleaned.isEmpty else { return nil }
        return Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX"))
    }

    var body: some View {
        Form {
            Section {
                TextField("contribute.name", text: $draft.name)
                TextField("contribute.affiliation", text: $draft.affiliation)
                TextField("contribute.address", text: $draft.address)
            } header: {
                Text("contribute.section.gym")
            }
            Section {
                TextField("contribute.phone", text: $draft.phone).keyboardType(.phonePad)
                TextField("gym.settings.email", text: $draft.email)
                    .keyboardType(.emailAddress).textInputAutocapitalization(.never)
                TextField("contribute.website", text: $draft.website)
                    .keyboardType(.URL).textInputAutocapitalization(.never)
                TextField("contribute.instagram", text: $draft.instagram).textInputAutocapitalization(.never)
                TextField("gym.settings.facebook", text: $draft.facebook).textInputAutocapitalization(.never)
            } header: {
                Text("contribute.section.contact")
            }
            Section {
                TextField("gym.settings.priceDropIn", text: $dropInText).keyboardType(.decimalPad)
                TextField("gym.settings.priceMonthly", text: $monthlyText).keyboardType(.decimalPad)
                TextField("gym.settings.priceKids", text: $kidsText).keyboardType(.decimalPad)
                Toggle("gym.settings.hasKids", isOn: $draft.hasKids)
                Toggle("gym.settings.hasWomen", isOn: $draft.hasWomenOnly)
            } header: {
                Text("gym.settings.prices")
            }
            Section {
                TextField("gym.settings.revolut.placeholder", text: $revolutText)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if !revolutValid {
                    Text("gym.settings.revolut.invalid").font(.footnote).foregroundStyle(.red)
                }
            } header: {
                Text("gym.settings.revolut")
            } footer: {
                Text("gym.settings.revolut.footer")
            }
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(draft.photoURLs, id: \.self) { url in
                            AsyncImage(url: url) { image in
                                image.resizable().scaledToFill()
                            } placeholder: {
                                Color.secondary.opacity(0.2)
                            }
                            .frame(width: 90, height: 90)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(alignment: .topTrailing) {
                                Button {
                                    draft.photoURLs.removeAll { $0 == url }
                                } label: {
                                    Image(systemName: "xmark.circle.fill").foregroundStyle(.white)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label("gym.settings.addPhoto", systemImage: "photo.badge.plus")
                }
                .disabled(draft.photoURLs.count >= 10)
            } header: {
                Text("gym.settings.photos")
            }
            if let message {
                Section { Text(message).font(.footnote) }
            }
        }
        .disabled(!canManage)
        .navigationTitle("gym.dash.settings")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("common.save") {
                    Task { await save() }
                }
                .disabled(!canManage || isSaving || !revolutValid)
            }
        }
        .task {
            if let current = try? await services.gymManagement.revolutURL(gymId: myGym.gymId) {
                revolutText = current
            }
        }
        .onChange(of: photoItem) { _, newValue in
            guard let newValue else { return }
            Task { await upload(newValue) }
        }
    }

    @MainActor
    private func upload(_ item: PhotosPickerItem) async {
        defer { photoItem = nil }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let jpeg = ImageCompressor.jpegData(from: data) else {
            message = String(localized: "gym.settings.photoError")
            return
        }
        do {
            let url = try await services.gymManagement.uploadGymPhoto(gymId: myGym.gymId, jpegData: jpeg)
            draft.photoURLs.append(url)
        } catch {
            message = error.localizedDescription
        }
    }

    @MainActor
    private func save() async {
        isSaving = true
        defer { isSaving = false }
        draft.priceDropIn = GymSettingsView.decimal(dropInText)
        draft.priceMonthly = GymSettingsView.decimal(monthlyText)
        draft.priceKids = GymSettingsView.decimal(kidsText)
        do {
            try await services.gymManagement.updateGymProfile(draft)
            try await services.gymManagement.setRevolutURL(gymId: myGym.gymId,
                                                           url: revolutText.trimmingCharacters(in: .whitespaces))
            message = String(localized: "gym.settings.saved")
        } catch {
            message = error.localizedDescription
        }
    }
}
