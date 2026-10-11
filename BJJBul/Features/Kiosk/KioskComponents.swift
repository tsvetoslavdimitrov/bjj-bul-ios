import SwiftUI

enum KioskClock {
    /// "HH:mm" in Bulgarian time.
    static func hhmm(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = Calendar.bulgaria.timeZone
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

/// Large numeric PIN pad. onSubmit returns false for a wrong PIN (the pad clears and shows an error).
struct KioskPinPad: View {
    let title: LocalizedStringKey
    let digits: ClosedRange<Int>
    let onSubmit: (String) -> Bool
    @State private var pin = ""
    @State private var wrong = false

    private let keys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "⌫", "0", "OK"]

    var body: some View {
        VStack(spacing: 20) {
            Text(title).font(.title).bold()
            HStack(spacing: 14) {
                ForEach(0..<max(digits.lowerBound, pin.count), id: \.self) { index in
                    Circle()
                        .fill(index < pin.count ? Color.primary : Color.secondary.opacity(0.25))
                        .frame(width: 18, height: 18)
                }
            }
            if wrong {
                Text("kiosk.pin.wrong").foregroundStyle(.red).font(.title3)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(110), spacing: 16), count: 3), spacing: 16) {
                ForEach(keys, id: \.self) { key in
                    Button {
                        tap(key)
                    } label: {
                        Text(verbatim: key)
                            .font(.system(size: 34, weight: .semibold))
                            .frame(width: 110, height: 80)
                            .background(RoundedRectangle(cornerRadius: 16)
                                .fill(key == "OK" ? Color.accentColor : Color.secondary.opacity(0.15)))
                            .foregroundStyle(key == "OK" ? Color.white : Color.primary)
                    }
                    .buttonStyle(.plain)
                    .disabled(key == "OK" && !digits.contains(pin.count))
                }
            }
        }
        .padding()
    }

    private func tap(_ key: String) {
        wrong = false
        if key == "⌫" {
            if !pin.isEmpty { pin.removeLast() }
        } else if key == "OK" {
            let accepted = onSubmit(pin)
            if !accepted { wrong = true }
            pin = ""
        } else if pin.count < digits.upperBound {
            pin.append(key)
            if digits.lowerBound == digits.upperBound && pin.count == digits.upperBound {
                let accepted = onSubmit(pin)
                if !accepted { wrong = true }
                pin = ""
            }
        }
    }
}

/// Name search: min 2 characters, short names + belt only (no emails or phones).
struct KioskSearchView: View {
    @Environment(AppServices.self) private var services
    let gymId: UUID
    let onPick: (KioskMember) -> Void
    @State private var query = ""
    @State private var results: [KioskMember] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("kiosk.search.title").font(.title).bold()
            TextField("kiosk.search.placeholder", text: $query)
                .font(.title2)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
            if query.trimmingCharacters(in: .whitespaces).count < 2 {
                Text("kiosk.search.min").foregroundStyle(.secondary)
            } else if results.isEmpty {
                Text("kiosk.search.none").foregroundStyle(.secondary)
            }
            ForEach(results) { member in
                Button {
                    onPick(member)
                } label: {
                    HStack {
                        Text(verbatim: member.shortName).font(.title2).bold()
                        Spacer()
                        if let belt = member.belt {
                            Text(LocalizedStringKey(belt.localizedKey)).font(.title3).foregroundStyle(.secondary)
                        }
                    }
                    .padding(18)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color.secondary.opacity(0.12)))
                }
                .buttonStyle(.plain)
            }
        }
        .task(id: query) {
            try? await Task.sleep(nanoseconds: 300_000_000)
            results = (try? await services.kiosk.searchMembers(gymId: gymId, query: query)) ?? []
        }
    }
}

struct KioskNewUserForm: View {
    let onSubmit: (KioskLeadDraft) -> Void
    @State private var name = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var belt: Belt = .white

    private var valid: Bool {
        name.trimmingCharacters(in: .whitespaces).count >= 2 && email.contains("@") && email.contains(".")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("kiosk.newUser").font(.title).bold()
            TextField("kiosk.form.name", text: $name).textFieldStyle(.roundedBorder).font(.title3)
            TextField("kiosk.form.email", text: $email)
                .textFieldStyle(.roundedBorder).font(.title3)
                .keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
            TextField("kiosk.form.phone", text: $phone)
                .textFieldStyle(.roundedBorder).font(.title3).keyboardType(.phonePad)
            Picker("profile.belt", selection: $belt) {
                ForEach(Belt.allCases, id: \.self) { item in
                    Text(LocalizedStringKey(item.localizedKey)).tag(item)
                }
            }
            .pickerStyle(.segmented)
            Text("kiosk.newUser.footer").font(.footnote).foregroundStyle(.secondary)
            Button {
                onSubmit(KioskLeadDraft(name: name.trimmingCharacters(in: .whitespaces),
                                        email: email.trimmingCharacters(in: .whitespaces),
                                        phone: phone.trimmingCharacters(in: .whitespaces), belt: belt))
            } label: {
                Text("kiosk.continue").font(.title2).bold().frame(maxWidth: .infinity, minHeight: 56)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!valid)
        }
    }
}

struct KioskGuestForm: View {
    let waiverText: String
    let onSubmit: (KioskGuestDraft) -> Void
    @State private var name = ""
    @State private var phone = ""
    @State private var email = ""
    @State private var accepted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("kiosk.guestDropIn").font(.title).bold()
            TextField("kiosk.form.name", text: $name).textFieldStyle(.roundedBorder).font(.title3)
            TextField("kiosk.form.phoneOptional", text: $phone)
                .textFieldStyle(.roundedBorder).font(.title3).keyboardType(.phonePad)
            TextField("kiosk.form.emailOptional", text: $email)
                .textFieldStyle(.roundedBorder).font(.title3)
                .keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
            Text("kiosk.waiver").font(.headline)
            ScrollView {
                Text(verbatim: waiverText.isEmpty ? String(localized: "kiosk.waiver.default") : waiverText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 180)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.1)))
            Toggle("kiosk.waiver.accept", isOn: $accepted).font(.title3)
            Button {
                onSubmit(KioskGuestDraft(name: name.trimmingCharacters(in: .whitespaces),
                                         phone: phone.trimmingCharacters(in: .whitespaces),
                                         email: email.trimmingCharacters(in: .whitespaces), waiverAccepted: accepted))
            } label: {
                Text("kiosk.continue").font(.title2).bold().frame(maxWidth: .infinity, minHeight: 56)
            }
            .buttonStyle(.borderedProminent)
            .disabled(name.trimmingCharacters(in: .whitespaces).count < 2 || !accepted)
        }
    }
}

struct KioskPlansView: View {
    @Environment(AppServices.self) private var services
    let gymId: UUID
    let guestOnly: Bool
    let onPick: (GymPassPlan) -> Void
    let onPayLater: () -> Void
    @State private var plans: [GymPassPlan] = []
    @State private var isLoading = true

    private var visible: [GymPassPlan] {
        guestOnly ? plans.filter { $0.kind == .oneOff && ($0.classCredits ?? 1) == 1 } : plans
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("kiosk.plans.title").font(.title).bold()
            if visible.isEmpty && !isLoading {
                Text("pass.buy.none").font(.title3).foregroundStyle(.secondary)
            }
            ForEach(visible) { plan in
                Button {
                    onPick(plan)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(verbatim: plan.name).font(.title2).bold()
                            if plan.kind == .oneOff {
                                Text("pass.summary \(plan.classCredits ?? 1) \(plan.validityDays ?? 30)")
                                    .font(.title3).foregroundStyle(.secondary)
                            } else {
                                Text(LocalizedStringKey(plan.period.localizedKey)).font(.title3).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text(verbatim: String(format: "%.2f %@", plan.price, plan.currency)).font(.title2).bold()
                    }
                    .padding(20)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color.secondary.opacity(0.12)))
                }
                .buttonStyle(.plain)
            }
            Button {
                onPayLater()
            } label: {
                Label("kiosk.payLater", systemImage: "clock").font(.title3)
            }
            .buttonStyle(.bordered)
        }
        .task {
            defer { isLoading = false }
            plans = (try? await services.gymManagement.gymPassPlans(gymId: gymId)) ?? []
        }
    }
}

/// Price, Revolut QR + reference, then staff confirm with the gym PIN.
struct KioskPayView: View {
    let plan: GymPassPlan
    let reference: String
    let onConfirm: (MemberPaymentMethod?, String) -> Void
    @State private var pendingMethod: MemberPaymentMethod?
    @State private var choosing = false
    @State private var payLater = false

    var body: some View {
        VStack(spacing: 20) {
            Text(verbatim: plan.name).font(.title).bold()
            Text(verbatim: String(format: "%.2f %@", plan.price, plan.currency)).font(.system(size: 56, weight: .heavy))
            if choosing {
                KioskPinPad(title: "kiosk.staffPin", digits: 4...6) { pin in
                    onConfirm(payLater ? nil : pendingMethod, pin)
                    choosing = false
                    return true
                }
                Button("common.cancel") { choosing = false }
                    .font(.title3)
            } else {
                if let url = plan.revolutURL {
                    HStack(alignment: .top, spacing: 24) {
                        QRCodeView(text: url.absoluteString)
                            .frame(width: 220, height: 220)
                            .padding(10)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        VStack(alignment: .leading, spacing: 8) {
                            Text("kiosk.pay.scanRevolut").font(.title3).bold()
                            Text("mypay.reference").font(.headline).foregroundStyle(.secondary)
                            Text(verbatim: reference).font(.title3.monospaced())
                            Text("kiosk.pay.referenceHint").font(.callout).foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Text("mypay.noRevolut").font(.title3).foregroundStyle(.secondary)
                }
                HStack(spacing: 16) {
                    payButton("kiosk.paidCash", method: .cash)
                    payButton("kiosk.paidRevolut", method: .revolut)
                }
                Button {
                    payLater = true
                    pendingMethod = nil
                    choosing = true
                } label: {
                    Label("kiosk.payLater", systemImage: "clock").font(.title3)
                }
                .buttonStyle(.bordered)
                Text("kiosk.pay.staffNote").font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private func payButton(_ key: LocalizedStringKey, method: MemberPaymentMethod) -> some View {
        Button {
            payLater = false
            pendingMethod = method
            choosing = true
        } label: {
            Text(key).font(.title2).bold().frame(maxWidth: .infinity, minHeight: 64)
        }
        .buttonStyle(.borderedProminent)
    }
}

struct KioskSuccessView: View {
    let name: String
    let belt: Belt?
    let credits: Int?
    let subscription: Bool
    let unpaid: Bool
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: unpaid ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                .font(.system(size: 96))
                .foregroundStyle(unpaid ? Color.orange : Color.green)
            Text("kiosk.success.welcome \(name)").font(.system(size: 44, weight: .heavy)).multilineTextAlignment(.center)
            if let belt {
                Text(LocalizedStringKey(belt.localizedKey)).font(.title2).foregroundStyle(.secondary)
            }
            if subscription {
                Text("kiosk.success.subscription").font(.title2)
            } else if let credits {
                Text("pass.creditsLeft \(credits)").font(.title2)
            }
            if unpaid {
                Text("kiosk.success.unpaid").font(.title3).foregroundStyle(.orange)
            }
            Button("kiosk.done") { onDone() }
                .font(.title2)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
        .task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if !Task.isCancelled { onDone() }
        }
    }
}
