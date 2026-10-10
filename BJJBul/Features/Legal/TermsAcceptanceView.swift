import SwiftUI

/// Required step after sign-up / first sign-in (and when the Terms version changes).
struct TermsAcceptanceView: View {
    @Environment(AppServices.self) private var services
    @State private var agreed = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("legal.accept.intro")
                    Text("legal.accept.zeroTolerance")
                        .bold()
                }
                Section {
                    NavigationLink("legal.terms") {
                        LegalDocumentView(document: .terms)
                    }
                    NavigationLink("legal.privacy") {
                        LegalDocumentView(document: .privacy)
                    }
                }
                Section {
                    Toggle("legal.accept.toggle", isOn: $agreed)
                    Button {
                        Task { await accept() }
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("legal.accept.continue")
                        }
                    }
                    .disabled(!agreed || isSaving)
                }
                Section {
                    Button("legal.accept.decline", role: .destructive) {
                        Task { await decline() }
                    }
                } footer: {
                    Text("legal.accept.declineFooter")
                }
                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("legal.accept.title")
            .navigationBarTitleDisplayMode(.inline)
        }
        .interactiveDismissDisabled()
    }

    @MainActor
    private func accept() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await services.users.acceptTerms(version: AppConfig.termsVersion)
            if var user = services.currentUser {
                user.termsAcceptedAt = Date()
                user.termsVersion = AppConfig.termsVersion
                services.currentUser = user
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func decline() async {
        try? await services.auth.signOut()
        await services.refreshSession()
    }
}
