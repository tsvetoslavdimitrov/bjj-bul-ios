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

    var body: some View {
        Form {
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

            Section("auth.email.title") {
                TextField("auth.email.placeholder", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if codeSent {
                    TextField("auth.code.placeholder", text: $code)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                    Button("auth.code.verify") {
                        Task { await verifyCode() }
                    }
                    .disabled(code.isEmpty || isWorking)
                    Text("auth.code.hint")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Button("auth.email.send") {
                        Task { await sendCode() }
                    }
                    .disabled(!email.contains("@") || isWorking)
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
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
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func sendCode() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await services.auth.sendEmailCode(to: email.trimmingCharacters(in: .whitespaces))
            codeSent = true
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func verifyCode() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await services.auth.verifyEmailCode(email: email.trimmingCharacters(in: .whitespaces),
                                                    code: code.trimmingCharacters(in: .whitespaces))
            await services.refreshSession()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
