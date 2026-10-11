import SwiftUI

/// Profile → My QR: rotating check-in QR (refreshes every 60 s) and the member PIN for kiosk name search.
struct MemberQRView: View {
    @Environment(AppServices.self) private var services
    @State private var qr: MemberQR?
    @State private var showStatic = false
    @State private var pin = ""
    @State private var pinMessage: String?
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                VStack(spacing: 12) {
                    if let qr {
                        QRCodeView(text: showStatic ? qr.staticPayload : qr.payload)
                            .frame(width: 240, height: 240)
                            .padding(12)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        if showStatic {
                            Text(verbatim: qr.memberCode).font(.title3.monospaced()).bold()
                        } else {
                            Text("qr.rotating").font(.caption).foregroundStyle(.secondary)
                        }
                    } else if let errorMessage {
                        Text(errorMessage).foregroundStyle(.red)
                    } else {
                        ProgressView().frame(height: 240)
                    }
                    Toggle("qr.static", isOn: $showStatic)
                }
                .frame(maxWidth: .infinity)
            } footer: {
                Text("qr.footer")
            }

            Section {
                SecureField("qr.pin.placeholder", text: $pin)
                    .keyboardType(.numberPad)
                Button("qr.pin.save") {
                    Task { await savePin() }
                }
                .disabled(pin.count != 4 || !pin.allSatisfy { $0.isNumber })
                if let pinMessage {
                    Text(pinMessage).font(.footnote)
                }
            } header: {
                Text(LocalizedStringKey((qr?.hasPin ?? false) ? "qr.pin.change" : "qr.pin.set"))
            } footer: {
                Text("qr.pin.footer")
            }
        }
        .navigationTitle("qr.title")
        .task {
            // Rotate while the screen is visible.
            while !Task.isCancelled {
                await load()
                try? await Task.sleep(nanoseconds: 60_000_000_000)
            }
        }
    }

    @MainActor
    private func load() async {
        do {
            qr = try await services.kiosk.myMemberQR()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func savePin() async {
        do {
            try await services.kiosk.setMemberPin(pin)
            pin = ""
            pinMessage = String(localized: "qr.pin.saved")
            qr?.hasPin = true
        } catch {
            pinMessage = error.localizedDescription
        }
    }
}
