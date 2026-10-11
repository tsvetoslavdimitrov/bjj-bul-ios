import SwiftUI

struct ProfileEditView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @State private var draft: AppUser
    @State private var gyms: [Gym] = []
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var smoothcompText: String

    private var smoothcompValid: Bool {
        let text = smoothcompText.trimmingCharacters(in: .whitespaces)
        return text.isEmpty || SmoothcompLink.normalized(text) != nil
    }

    init(user: AppUser) {
        _draft = State(initialValue: user)
        _smoothcompText = State(initialValue: user.smoothcompProfileURL?.absoluteString ?? "")
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
                Section {
                    TextField("athlete.team", text: Binding(
                        get: { draft.team ?? "" },
                        set: { draft.team = $0 }
                    ))
                    Picker("athlete.teamGym", selection: $draft.teamGymId) {
                        Text("profile.homeGym.none").tag(UUID?.none)
                        ForEach(gyms) { gym in
                            Text(gym.name).tag(UUID?.some(gym.id))
                        }
                    }
                    .pickerStyle(.navigationLink)
                } header: {
                    Text("athlete.section.team")
                }
                Section {
                    TextField("athlete.smoothcomp.placeholder", text: $smoothcompText)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if !smoothcompValid {
                        Text("athlete.smoothcomp.invalid")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("athlete.smoothcomp")
                } footer: {
                    Text("athlete.smoothcomp.footer")
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
                    .disabled(isSaving || !smoothcompValid)
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
        let text = smoothcompText.trimmingCharacters(in: .whitespaces)
        draft.smoothcompProfileURL = text.isEmpty ? nil : SmoothcompLink.normalized(text)
        do {
            try await services.users.update(draft)
            services.currentUser = draft
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
