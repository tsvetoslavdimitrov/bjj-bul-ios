import SwiftUI

struct ProfileEditView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @State private var draft: AppUser
    @State private var gyms: [Gym] = []
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(user: AppUser) {
        _draft = State(initialValue: user)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("profile.section.about") {
                    TextField("profile.displayName", text: $draft.displayName)
                }
                Section("profile.section.rank") {
                    Picker("profile.belt", selection: $draft.belt) {
                        ForEach(Belt.allCases, id: \.self) { belt in
                            Text(LocalizedStringKey(belt.localizedKey)).tag(belt)
                        }
                    }
                    Stepper(value: $draft.stripes, in: 0...4) {
                        Text("profile.stripes \(draft.stripes)")
                    }
                }
                Section("profile.homeGym") {
                    Picker("profile.homeGym", selection: $draft.homeGymId) {
                        Text("profile.homeGym.none").tag(UUID?.none)
                        ForEach(gyms) { gym in
                            Text(gym.name).tag(UUID?.some(gym.id))
                        }
                    }
                    .pickerStyle(.navigationLink)
                }
                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("profile.edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.save") {
                        Task { await save() }
                    }
                    .disabled(isSaving)
                }
            }
            .task {
                gyms = (try? await services.gyms.gyms(cityId: nil)) ?? []
            }
        }
    }

    @MainActor
    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await services.users.update(draft)
            services.currentUser = draft
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
