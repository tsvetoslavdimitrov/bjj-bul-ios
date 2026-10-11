import SwiftUI
import AuthenticationServices

struct SignInView: View {
    @Environment(AppServices.self) private var services
    @State private var nonce = ""
    @State private var email = ""
    @State private var code = ""
    @State private var codeSent = false
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var infoMessage: String?
    @State private var password = ""
    @State private var showPassword = false
    @State private var mode: EmailMode = .signIn
    @State private var cooldown = 0
    @State private var cooldownTask: Task<Void, Never>?

    enum EmailMode: Hashable {
        case signIn, signUp
    }

    private var trimmedEmail: String { email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
    private var emailValid: Bool { trimmedEmail.contains("@") && trimmedEmail.contains(".") }
    private var codeValid: Bool { code.count >= 6 && code.count <= 10 }

    var body: some View {
        Form {
            Section {
                LogoHeader()
            }
            .listRowBackground(Color.clear)

            Section {
                SignInWithAppleButton(.signIn) { request in
                    let raw = Nonce.random()
                    nonce = raw
                    request.requestedScopes = [.fullName, .email]
                    request.nonce = Nonce.sha256(raw)
                } onCompletion: { result in
                    handleApple(result)
                }
                .frame(height: 48)
            } footer: {
                Text("auth.apple.footer")
            }

            Section {
                Picker("auth.mode", selection: $mode) {
                    Text("auth.mode.signIn").tag(EmailMode.signIn)
                    Text("auth.mode.signUp").tag(EmailMode.signUp)
                }
                .pickerStyle(.segmented)
                TextField("auth.email.placeholder", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                HStack {
                    Group {
                        if showPassword {
                            TextField("auth.password", text: $password)
                        } else {
                            SecureField("auth.password", text: $password)
                        }
                    }
                    .textContentType(mode == .signUp ? .newPassword : .password)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    Button {
                        showPassword.toggle()
                    } label: {
                        Image(systemName: showPassword ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(Text("auth.password.toggle"))
                }
                Button {
                    Task { await submitPassword() }
                } label: {
                    HStack {
                        Text(LocalizedStringKey(mode == .signIn ? "auth.signIn" : "auth.signUp")).bold()
                        if isWorking {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(!emailValid || password.count < 6 || isWorking)
                if mode == .signUp {
                    Text("auth.password.rules").font(.footnote).foregroundStyle(.secondary)
                } else {
                    Button("auth.forgot") {
                        Task { await forgotPassword() }
                    }
                    .font(.footnote)
                    .disabled(!emailValid || isWorking)
                }
            } header: {
                Text("auth.email.title")
            }

            if let infoMessage {
                Section {
                    Label(infoMessage, systemImage: "envelope.badge")
                        .foregroundStyle(.green)
                }
            }

            if let errorMessage {
                Section {
                    Text(verbatim: errorMessage).foregroundStyle(.red)
                    Button {
                        self.errorMessage = nil
                    } label: {
                        Text("auth.dismissError").font(.footnote)
                    }
                }
            }

            Section {
                if codeSent {
                    TextField("auth.code.placeholder", text: $code)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .font(.title3.monospacedDigit())
                    Button("auth.code.verify") {
                        Task { await verifyCode() }
                    }
                    .disabled(!codeValid || isWorking)
                    Text("auth.code.hint")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button {
                        Task { await sendCode() }
                    } label: {
                        if cooldown > 0 {
                            Text(String(format: NSLocalizedString("auth.code.resendIn %lld", comment: ""), cooldown))
                        } else {
                            Text("auth.code.resend")
                        }
                    }
                    .disabled(cooldown > 0 || isWorking || !emailValid)
                    Button("auth.code.startOver") {
                        startOver()
                    }
                    .foregroundStyle(.secondary)
                } else {
                    Button("auth.email.send") {
                        Task { await sendCode() }
                    }
                    .disabled(!emailValid || isWorking)
                }
            } header: {
                Text("auth.code.title")
            }

            Section {
                Text("legal.signIn.notice")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            LegalLinksSection()
        }
        .onChange(of: email) { _, _ in clearMessages() }
        .onChange(of: password) { _, _ in clearMessages() }
        .onChange(of: mode) { _, _ in clearMessages() }
        .onChange(of: code) { _, newValue in
            // digits only, max 10 (the screenshot had pasted letters)
            let digits = String(newValue.filter { $0.isASCII && $0.isNumber }.prefix(10))
            if digits != newValue {
                code = digits
            }
            errorMessage = nil
        }
        .onDisappear {
            cooldownTask?.cancel()
        }
    }

    private func handleApple(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard
                let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                let tokenData = credential.identityToken,
                let token = String(data: tokenData, encoding: .utf8)
            else {
                errorMessage = String(localized: "auth.error.generic")
                return
            }
            let parts = [credential.fullName?.givenName, credential.fullName?.familyName]
            let fullName = parts.compactMap { $0 }.joined(separator: " ")
            Task { await signInWithApple(token: token, fullName: fullName) }
        case .failure(let error):
            if let authError = error as? ASAuthorizationError, authError.code == .canceled { return }
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func signInWithApple(token: String, fullName: String) async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await services.auth.signInWithApple(idToken: token, nonce: nonce)
            await services.refreshSession()
            // Apple only shares the name on first sign-in, so store it right away.
            if var user = services.currentUser, user.displayName.isEmpty, !fullName.isEmpty {
                user.displayName = fullName
                try? await services.users.update(user)
                services.currentUser = user
            }
        } catch {
            errorMessage = AuthErrorText.message(for: error)
        }
    }

    private func clearMessages() {
        errorMessage = nil
        infoMessage = nil
    }

    private func startOver() {
        codeSent = false
        code = ""
        clearMessages()
        cooldownTask?.cancel()
        cooldown = 0
    }

    private func startCooldown() {
        cooldownTask?.cancel()
        cooldown = 60
        cooldownTask = Task { @MainActor in
            while cooldown > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
                cooldown -= 1
            }
        }
    }

    @MainActor
    private func submitPassword() async {
        isWorking = true
        defer { isWorking = false }
        clearMessages()
        do {
            if mode == .signUp {
                let hasSession = try await services.auth.signUp(email: trimmedEmail, password: password)
                if hasSession {
                    await services.refreshSession()
                } else {
                    infoMessage = String(localized: "auth.signUp.confirm")
                }
            } else {
                try await services.auth.signIn(email: trimmedEmail, password: password)
                await services.refreshSession()
            }
        } catch {
            errorMessage = AuthErrorText.message(for: error)
        }
    }

    @MainActor
    private func forgotPassword() async {
        isWorking = true
        defer { isWorking = false }
        clearMessages()
        do {
            try await services.auth.sendPasswordReset(email: trimmedEmail)
            infoMessage = String(localized: "auth.forgot.sent")
        } catch {
            errorMessage = AuthErrorText.message(for: error)
        }
    }

    @MainActor
    private func sendCode() async {
        isWorking = true
        defer { isWorking = false }
        clearMessages()
        do {
            try await services.auth.sendEmailCode(to: trimmedEmail)
            codeSent = true
            code = ""
            startCooldown()
        } catch {
            errorMessage = AuthErrorText.message(for: error)
            // a rate-limited send still lets the user wait and retry
            if codeSent { startCooldown() }
        }
    }

    @MainActor
    private func verifyCode() async {
        isWorking = true
        defer { isWorking = false }
        clearMessages()
        do {
            try await services.auth.verifyEmailCode(email: trimmedEmail, code: code)
            await services.refreshSession()
        } catch {
            errorMessage = AuthErrorText.message(for: error)
        }
    }
}

/// Maps Supabase auth errors to short localized messages.
enum AuthErrorText {
    static func message(for error: Error) -> String {
        let text = (String(describing: error) + " " + error.localizedDescription).lowercased()
        if text.contains("invalid login credentials") || text.contains("invalid_credentials") {
            return String(localized: "auth.error.wrongPassword")
        }
        if text.contains("email not confirmed") || text.contains("email_not_confirmed") {
            return String(localized: "auth.error.notConfirmed")
        }
        if text.contains("rate limit") || text.contains("over_email_send_rate_limit") || text.contains("429")
            || text.contains("for security purposes") {
            return String(localized: "auth.error.rateLimited")
        }
        if text.contains("expired") || text.contains("otp_expired") || (text.contains("invalid") && text.contains("token")) {
            return String(localized: "auth.error.codeInvalid")
        }
        if text.contains("already registered") || text.contains("user_already_exists") {
            return String(localized: "auth.error.exists")
        }
        if text.contains("weak") || text.contains("password should") {
            return String(localized: "auth.error.weakPassword")
        }
        if text.contains("offline") || text.contains("network") || text.contains("timed out") {
            return String(localized: "auth.error.network")
        }
        return String(localized: "auth.error.generic")
    }
}

/// Shown after opening a password-recovery link (bjjbul://login?...type=recovery).
struct NewPasswordView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("auth.password.new", text: $password)
                        .textContentType(.newPassword)
                    Button {
                        Task { await save() }
                    } label: {
                        if isWorking { ProgressView() } else { Text("common.save").bold() }
                    }
                    .disabled(password.count < 6 || isWorking)
                } header: {
                    Text("auth.password.newTitle")
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
            }
            .navigationTitle("auth.password.newTitle")
            .onChange(of: password) { _, _ in errorMessage = nil }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.close") { dismiss() }
                }
            }
        }
    }

    @MainActor
    private func save() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await services.auth.updatePassword(password)
            services.needsNewPassword = false
            dismiss()
        } catch {
            errorMessage = AuthErrorText.message(for: error)
        }
    }
}
