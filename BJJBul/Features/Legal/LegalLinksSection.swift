import SwiftUI

/// Terms, Privacy and contact links for Profile / Settings and the sign-in screen.
struct LegalLinksSection: View {
    var body: some View {
        Section("legal.section") {
            NavigationLink("legal.terms") {
                LegalDocumentView(document: .terms)
            }
            NavigationLink("legal.privacy") {
                LegalDocumentView(document: .privacy)
            }
            if let url = AppConfig.contactURL {
                Link(destination: url) {
                    LabeledContent("legal.contact", value: AppConfig.contactEmail)
                }
            }
        }
    }
}
