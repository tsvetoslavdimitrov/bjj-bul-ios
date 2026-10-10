import SwiftUI

struct SuggestEditView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    let entityType: String
    let entityId: UUID?
    let title: String
    @State private var message = ""
    @State private var isSending = false
    @State private var sent = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                if services.isSignedIn {
                    Section {
                        Text(title).font(.headline)
                        TextEditor(text: $message)
                            .frame(minHeight: 160)
                    } footer: {
                        Text("suggest.footer")
                    }
                    if sent {
                        Section {
                            Label("suggest.thanks", systemImage: "checkmark.circle")
                                .foregroundStyle(.green)
                        }
                    }
                    if let errorMessage {
                        Section {
                            Text(errorMessage).foregroundStyle(.red)
                        }
                    }
                } else {
                    Section {
                        Text("suggest.signInRequired")
                    }
                }
            }
            .navigationTitle("gym.suggestEdit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.close") { dismiss() }
                }
                if services.isSignedIn && !sent {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("suggest.send") {
                            Task { await send() }
                        }
                        .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
                    }
                }
            }
        }
    }

    @MainActor
    private func send() async {
        isSending = true
        defer { isSending = false }
        do {
            try await services.users.submitSuggestion(entityType: entityType, entityId: entityId,
                                                      message: message)
            sent = true
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
