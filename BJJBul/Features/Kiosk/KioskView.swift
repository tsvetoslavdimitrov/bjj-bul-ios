import SwiftUI
import Combine
import UIKit

/// Who is paying / checking in.
enum KioskPayer: Hashable {
    /// proof: QR payload, member PIN, or "staff:<pin>" for new registrations (nil until known).
    case member(KioskMember, proof: String?)
    case guest(KioskGuestDraft)
}

enum KioskStep: Hashable {
    case home
    case who
    case scan
    case search
    case pin(KioskMember)
    case newUser
    case guest
    case blocked(KioskMember, proof: String)
    case plans(KioskPayer)
    case pay(KioskPayer, GymPassPlan)
    case success(name: String, belt: Belt?, credits: Int?, subscription: Bool, unpaid: Bool)
}

/// Full-screen, locked front-desk kiosk.
struct KioskView: View {
    @Environment(AppServices.self) private var services
    let myGym: MyGym
    let waiverText: String
    let onExit: () -> Void

    @State private var step: KioskStep
    @State private var classes: [ClassSchedule] = []
    @State private var selectedClass: ClassSchedule?
    @State private var lastActivity = Date()
    @State private var showExit = false
    @State private var message: String?
    @State private var isBusy = false

    init(myGym: MyGym, waiverText: String, initialStep: KioskStep = .home, onExit: @escaping () -> Void) {
        self.myGym = myGym
        self.waiverText = waiverText
        self.onExit = onExit
        _step = State(initialValue: initialStep)
    }

    private let idleTimeout: TimeInterval = 60
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color(.systemBackground).ignoresSafeArea()
            VStack(spacing: 0) {
                header
                Divider()
                ScrollView {
                    content
                        .frame(maxWidth: 820)
                        .padding(32)
                        .frame(maxWidth: .infinity)
                }
            }
            Button {
                showExit = true
            } label: {
                Image(systemName: "lock.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .padding(20)
            }
            .accessibilityLabel(Text("kiosk.exit"))
            if isBusy {
                Color.black.opacity(0.15).ignoresSafeArea()
                ProgressView().controlSize(.large)
            }
        }
        .persistentSystemOverlays(.hidden)
        .statusBarHidden(true)
        .interactiveDismissDisabled(true)
        .simultaneousGesture(TapGesture().onEnded { lastActivity = Date() })
        .onReceive(ticker) { now in
            if case .home = step { return }
            if case .success = step { return }
            if now.timeIntervalSince(lastActivity) > idleTimeout { goHome() }
        }
        .sheet(isPresented: $showExit) {
            KioskPinPad(title: "kiosk.exit.title", digits: 4...6) { pin in
                if LocalKioskPin.verify(pin, gymId: myGym.gymId) {
                    showExit = false
                    onExit()
                    return true
                }
                return false
            }
            .presentationDetents([.large])
        }
        .task {
            let all = (try? await services.gyms.schedule(gymId: myGym.gymId)) ?? []
            classes = all.filter { $0.weekday == GymDates.isoWeekday(Date()) }.sorted { $0.startTime < $1.startTime }
        }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: myGym.name).font(.system(size: 34, weight: .bold))
                if let selectedClass, !isHome {
                    HStack(spacing: 6) {
                        Text(verbatim: "\(selectedClass.startTime)–\(selectedClass.endTime) ·")
                        Text(LocalizedStringKey("class.\(selectedClass.type.rawValue)"))
                    }
                    .font(.title3)
                    .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if !isHome {
                Button {
                    goHome()
                } label: {
                    Label("kiosk.home", systemImage: "house.fill").font(.title3)
                }
                .buttonStyle(.bordered)
                .padding(.trailing, 56)
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 20)
    }

    private var isHome: Bool {
        if case .home = step { return true }
        return false
    }

    @ViewBuilder
    private var content: some View {
        if let message {
            Text(message)
                .font(.title3)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 12)
        }
        switch step {
        case .home:
            homeView
        case .who:
            whoView
        case .scan:
            scanView
        case .search:
            KioskSearchView(gymId: myGym.gymId) { member in
                message = nil
                if member.hasPin {
                    step = .pin(member)
                } else {
                    message = String(localized: "kiosk.noPin")
                }
            }
        case .pin(let member):
            VStack(spacing: 16) {
                Text(verbatim: member.shortName).font(.largeTitle).bold()
                KioskPinPad(title: "kiosk.memberPin", digits: 4...4) { pin in
                    Task { await checkIn(member: member, proof: pin, allowUnpaid: false) }
                    return true
                }
            }
        case .newUser:
            KioskNewUserForm { draft in
                Task { await register(draft) }
            }
        case .guest:
            KioskGuestForm(waiverText: waiverText) { draft in
                message = nil
                step = .plans(.guest(draft))
            }
        case .blocked(let member, let proof):
            blockedView(member: member, proof: proof)
        case .plans(let payer):
            KioskPlansView(gymId: myGym.gymId, guestOnly: isGuest(payer)) { plan in
                message = nil
                step = .pay(payer, plan)
            } onPayLater: {
                Task { await payLater(payer) }
            }
        case .pay(let payer, let plan):
            KioskPayView(plan: plan, reference: reference(for: payer)) { method, staffPin in
                Task { await pay(payer, plan: plan, method: method, staffPin: staffPin) }
            }
        case .success(let name, let belt, let credits, let subscription, let unpaid):
            KioskSuccessView(name: name, belt: belt, credits: credits, subscription: subscription, unpaid: unpaid) {
                goHome()
            }
        }
    }

    // MARK: - Screens

    private var currentClassId: UUID? {
        let now = KioskClock.hhmm(Date())
        return classes.first { item in
            item.endTime >= now && ClassEditorView.hhmm(ClassEditorView.date(from: item.startTime).addingTimeInterval(-30 * 60)) <= now
        }?.id
    }

    private var homeView: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("kiosk.home.title").font(.system(size: 40, weight: .heavy))
            Text(verbatim: BGDate.string(Date(), date: .full, time: .none)).font(.title2).foregroundStyle(.secondary)
            if classes.isEmpty {
                Text("gym.today.none").font(.title3).foregroundStyle(.secondary)
            }
            ForEach(classes) { item in
                bigButton(color: item.id == currentClassId ? Color.accentColor : Color.secondary.opacity(0.15),
                          foreground: item.id == currentClassId ? .white : .primary) {
                    selectedClass = item
                    message = nil
                    step = .who
                } label: {
                    HStack {
                        Text(verbatim: "\(item.startTime)–\(item.endTime)").font(.system(size: 30, weight: .bold).monospacedDigit())
                        Text(LocalizedStringKey("class.\(item.type.rawValue)")).font(.title)
                        Spacer()
                        if item.id == currentClassId {
                            Text("kiosk.now").font(.headline)
                        }
                    }
                }
            }
            bigButton(color: Color.secondary.opacity(0.15), foreground: .primary) {
                selectedClass = nil
                message = nil
                step = .who
            } label: {
                Label("kiosk.openMat", systemImage: "figure.martial.arts").font(.title)
            }
        }
    }

    private var whoView: some View {
        VStack(spacing: 18) {
            Text("kiosk.who").font(.system(size: 36, weight: .bold)).frame(maxWidth: .infinity, alignment: .leading)
            bigButton(color: .accentColor, foreground: .white) { step = .scan } label: {
                Label("kiosk.member.scan", systemImage: "qrcode.viewfinder").font(.title)
            }
            bigButton(color: Color.secondary.opacity(0.15), foreground: .primary) { step = .search } label: {
                Label("kiosk.member.search", systemImage: "magnifyingglass").font(.title)
            }
            bigButton(color: Color.secondary.opacity(0.15), foreground: .primary) { step = .newUser } label: {
                Label("kiosk.newUser", systemImage: "person.badge.plus").font(.title)
            }
            bigButton(color: Color.secondary.opacity(0.15), foreground: .primary) { step = .guest } label: {
                Label("kiosk.guestDropIn", systemImage: "ticket").font(.title)
            }
        }
    }

    private var scanView: some View {
        VStack(spacing: 16) {
            Text("kiosk.scan.title").font(.title).bold()
            QRScannerView { code in
                Task { await scanned(code) }
            }
            .frame(height: 420)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            Text("kiosk.scan.hint").font(.title3).foregroundStyle(.secondary)
        }
    }

    private func blockedView(member: KioskMember, proof: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 64)).foregroundStyle(.orange)
            Text(verbatim: member.shortName).font(.largeTitle).bold()
            Text("kiosk.noCredits").font(.title2).multilineTextAlignment(.center)
            bigButton(color: .accentColor, foreground: .white) {
                step = .plans(.member(member, proof: proof))
            } label: {
                Label("kiosk.buyPass", systemImage: "ticket.fill").font(.title)
            }
            bigButton(color: Color.secondary.opacity(0.15), foreground: .primary) {
                Task { await checkIn(member: member, proof: proof, allowUnpaid: true) }
            } label: {
                Label("kiosk.payLater", systemImage: "clock").font(.title)
            }
        }
    }

    private func bigButton<Content: View>(color: Color, foreground: Color, action: @escaping () -> Void,
                                        @ViewBuilder label: () -> Content) -> some View {
        Button(action: action) {
            label()
                .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .foregroundStyle(foreground)
                .background(RoundedRectangle(cornerRadius: 18).fill(color))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func goHome() {
        step = .home
        selectedClass = nil
        message = nil
        isBusy = false
        lastActivity = Date()
    }

    private func isGuest(_ payer: KioskPayer) -> Bool {
        if case .guest = payer { return true }
        return false
    }

    private func reference(for payer: KioskPayer) -> String {
        let month = String(EventDates.string(from: Date()).prefix(7))
        switch payer {
        case .member(let member, _):
            return PassReference.make(slug: myGym.slug, userId: member.userId, month: Date())
        case .guest(let draft):
            let letters = draft.name.lowercased().filter { $0.isLetter }.prefix(6)
            return "\(myGym.slug)-guest-\(letters)-\(month)"
        }
    }

    @MainActor
    private func scanned(_ code: String) async {
        guard case .scan = step else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            guard let member = try await services.kiosk.resolveQR(gymId: myGym.gymId, payload: code) else {
                message = String(localized: "kiosk.scan.invalid")
                return
            }
            isBusy = false
            await checkIn(member: member, proof: code, allowUnpaid: false)
        } catch {
            message = error.localizedDescription
        }
    }

    @MainActor
    private func checkIn(member: KioskMember, proof: String, allowUnpaid: Bool) async {
        isBusy = true
        defer { isBusy = false }
        do {
            let result = try await services.kiosk.checkIn(gymId: myGym.gymId, classId: selectedClass?.id,
                                                         userId: member.userId, proof: proof, allowUnpaid: allowUnpaid)
            let name = result.shortName ?? member.shortName
            switch result.kind {
            case .ok, .unpaid, .already:
                if result.kind == .already { message = nil }
                step = .success(name: name, belt: result.belt ?? member.belt,
                                credits: result.hasSubscription ? nil : result.creditsLeft,
                                subscription: result.hasSubscription, unpaid: result.kind == .unpaid)
            case .noCredits:
                message = nil
                step = .blocked(member, proof: proof)
            case .badProof:
                message = String(localized: "kiosk.badProof")
            case .notMember:
                message = String(localized: "kiosk.notMember")
            }
        } catch {
            message = error.localizedDescription
        }
    }

    @MainActor
    private func register(_ draft: KioskLeadDraft) async {
        isBusy = true
        defer { isBusy = false }
        do {
            let leadId = try await services.kiosk.createLead(gymId: myGym.gymId, draft: draft)
            let userId = try await services.kiosk.inviteLead(leadId: leadId)
            let member = KioskMember(userId: userId, shortName: KioskView.shortName(draft.name), belt: draft.belt, hasPin: false)
            message = nil
            step = .plans(.member(member, proof: nil))
        } catch {
            message = error.localizedDescription
        }
    }

    @MainActor
    private func payLater(_ payer: KioskPayer) async {
        switch payer {
        case .member(let member, let proof):
            if let proof {
                await checkIn(member: member, proof: proof, allowUnpaid: true)
            } else {
                // New registration: staff vouch with the PIN on the payment screen instead.
                message = String(localized: "kiosk.payLater.staff")
            }
        case .guest(let draft):
            isBusy = true
            defer { isBusy = false }
            do {
                try await services.kiosk.guestCheckIn(gymId: myGym.gymId, classId: selectedClass?.id, draft: draft,
                                                      planId: nil, method: nil, staffPin: "")
                step = .success(name: KioskView.shortName(draft.name), belt: nil, credits: nil,
                                subscription: false, unpaid: true)
            } catch {
                message = KioskView.describe(error)
            }
        }
    }

    @MainActor
    private func pay(_ payer: KioskPayer, plan: GymPassPlan, method: MemberPaymentMethod?, staffPin: String) async {
        isBusy = true
        defer { isBusy = false }
        do {
            switch payer {
            case .member(let member, let proof):
                if let method {
                    _ = try await services.kiosk.recordPayment(gymId: myGym.gymId, userId: member.userId, planId: plan.id,
                                                               method: method, staffPin: staffPin)
                }
                isBusy = false
                await checkIn(member: member, proof: proof ?? "staff:\(staffPin)", allowUnpaid: method == nil)
            case .guest(let draft):
                try await services.kiosk.guestCheckIn(gymId: myGym.gymId, classId: selectedClass?.id, draft: draft,
                                                      planId: plan.id, method: method, staffPin: staffPin)
                step = .success(name: KioskView.shortName(draft.name), belt: nil, credits: nil,
                                subscription: false, unpaid: method == nil)
            }
        } catch {
            message = KioskView.describe(error)
        }
    }

    static func describe(_ error: Error) -> String {
        let text = String(describing: error)
        if text.contains("bad_staff_pin") { return String(localized: "kiosk.badStaffPin") }
        if text.contains("waiver_required") { return String(localized: "kiosk.waiverRequired") }
        return error.localizedDescription
    }

    static func shortName(_ name: String) -> String {
        let parts = name.split(separator: " ").map(String.init)
        guard let first = parts.first else { return "—" }
        if parts.count == 1 { return first }
        return "\(first) \(parts[parts.count - 1].prefix(1))."
    }
}
