import SwiftUI

/// My gym → Kiosk: set the exit PIN and waiver, then start the locked front-desk screen.
struct KioskSetupView: View {
    @Environment(AppServices.self) private var services
    let myGym: MyGym
    @State private var pin = ""
    @State private var pinRepeat = ""
    @State private var saveAsGymPin = true
    @State private var waiver = ""
    @State private var settings: KioskSettings?
    @State private var isRunning = false
    @State private var errorMessage: String?
    @State private var isSaving = false

    private var pinOK: Bool { LocalKioskPin.isValid(pin) && pin == pinRepeat }

    var body: some View {
        Form {
            Section {
                SecureField("kiosk.pin", text: $pin).keyboardType(.numberPad)
                SecureField("kiosk.pin.repeat", text: $pinRepeat).keyboardType(.numberPad)
                Toggle("kiosk.pin.gym", isOn: $saveAsGymPin)
                if !pin.isEmpty && !pinOK {
                    Text("kiosk.pin.invalid").font(.footnote).foregroundStyle(.red)
                }
            } header: {
                Text("kiosk.pin.section")
            } footer: {
                Text("kiosk.pin.footer")
            }
            Section {
                TextEditor(text: $waiver).frame(minHeight: 140)
            } header: {
                Text("kiosk.waiver")
            } footer: {
                Text("kiosk.waiver.footer")
            }
            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red) }
            }
            Section {
                Button {
                    Task { await start() }
                } label: {
                    Label("kiosk.start", systemImage: "rectangle.inset.filled.and.person.filled")
                        .font(.headline)
                }
                .disabled(!pinOK || isSaving || !myGym.hasAccess)
                NavigationLink {
                    KioskAttendanceView(myGym: myGym)
                } label: {
                    Label("kiosk.attendance", systemImage: "list.bullet.clipboard")
                }
            } footer: {
                Text("kiosk.guidedAccess")
            }
        }
        .navigationTitle("kiosk.title")
        .task {
            if let loaded = try? await services.kiosk.settings(gymId: myGym.gymId) {
                settings = loaded
                waiver = loaded.waiverText
            }
        }
        .fullScreenCover(isPresented: $isRunning) {
            KioskView(myGym: myGym, waiverText: waiver) {
                isRunning = false
            }
        }
    }

    @MainActor
    private func start() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await services.kiosk.saveSettings(gymId: myGym.gymId, pin: saveAsGymPin ? pin : nil, waiver: waiver)
            LocalKioskPin.save(pin, gymId: myGym.gymId)
            pin = ""
            pinRepeat = ""
            errorMessage = nil
            isRunning = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Staff: today's check-ins (members + guests), refreshed every 15 s.
struct KioskAttendanceView: View {
    @Environment(AppServices.self) private var services
    let myGym: MyGym
    @State private var rows: [KioskAttendanceRow] = []
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                Text("kiosk.attendance.count \(rows.count) \(rows.filter { $0.unpaid }.count)")
                    .font(.subheadline)
            }
            if rows.isEmpty {
                Text("kiosk.attendance.none").foregroundStyle(.secondary)
            }
            ForEach(rows) { row in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: row.displayName).font(.headline)
                        HStack(spacing: 6) {
                            if let start = row.classStart {
                                Text(verbatim: start)
                            }
                            if let belt = row.belt {
                                Text(LocalizedStringKey(belt.localizedKey))
                            }
                            if let credits = row.creditsLeft, credits > 0 {
                                Text("pass.creditsLeft \(credits)")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if row.isGuest {
                        badge("kiosk.guest", color: .blue)
                    }
                    if row.unpaid {
                        badge("kiosk.unpaid", color: .red)
                    }
                    Text(verbatim: BGDate.string(row.createdAt, date: .none, time: .short))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
        }
        .navigationTitle("kiosk.attendance")
        .refreshable { await load() }
        .task {
            while !Task.isCancelled {
                await load()
                try? await Task.sleep(nanoseconds: 15_000_000_000)
            }
        }
    }

    private func badge(_ key: LocalizedStringKey, color: Color) -> some View {
        Text(key)
            .font(.caption2).bold()
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.18)))
            .foregroundStyle(color)
    }

    @MainActor
    private func load() async {
        do {
            rows = try await services.kiosk.attendanceToday(gymId: myGym.gymId)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
