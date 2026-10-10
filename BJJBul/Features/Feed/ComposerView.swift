import SwiftUI
import PhotosUI

struct ComposerView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    let onPosted: () -> Void

    @State private var text = ""
    @State private var type: PostType = .progress
    @State private var gymId: UUID?
    @State private var gyms: [Gym] = []
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var images: [Data] = []
    @State private var isLoadingImages = false
    @State private var isPosting = false
    @State private var errorMessage: String?

    private let maxPhotos = 4
    private let maxLength = 2000

    private var canPost: Bool {
        let hasText = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return (hasText || !images.isEmpty) && text.count <= maxLength && !isPosting && !isLoadingImages
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $text)
                        .frame(minHeight: 140)
                } footer: {
                    Text(verbatim: "\(text.count)/\(maxLength)")
                }

                Section("composer.details") {
                    Picker("composer.type", selection: $type) {
                        ForEach(PostType.allCases, id: \.self) { item in
                            Text(LocalizedStringKey(item.localizedKey)).tag(item)
                        }
                    }
                    Picker("composer.gym", selection: $gymId) {
                        Text("composer.gym.none").tag(UUID?.none)
                        ForEach(gyms) { gym in
                            Text(gym.name).tag(UUID?.some(gym.id))
                        }
                    }
                    .pickerStyle(.navigationLink)
                }

                Section("composer.photos") {
                    PhotosPicker(selection: $pickerItems, maxSelectionCount: maxPhotos, matching: .images) {
                        Label("composer.addPhotos", systemImage: "photo.on.rectangle")
                    }
                    if isLoadingImages {
                        ProgressView()
                    }
                    if !images.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(images.indices, id: \.self) { index in
                                    if let uiImage = UIImage(data: images[index]) {
                                        Image(uiImage: uiImage)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 80, height: 80)
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                    }
                                }
                            }
                        }
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("composer.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isPosting {
                        ProgressView()
                    } else {
                        Button("composer.post") {
                            Task { await post() }
                        }
                        .disabled(!canPost)
                    }
                }
            }
            .onChange(of: pickerItems) { _, newItems in
                Task { await loadImages(newItems) }
            }
            .task {
                gyms = (try? await services.gyms.gyms(cityId: nil)) ?? []
                if let home = services.currentUser?.homeGymId {
                    gymId = home
                }
            }
        }
    }

    @MainActor
    private func loadImages(_ items: [PhotosPickerItem]) async {
        isLoadingImages = true
        defer { isLoadingImages = false }
        var loaded: [Data] = []
        for item in items.prefix(maxPhotos) {
            if let raw = try? await item.loadTransferable(type: Data.self),
               let jpeg = ImageCompressor.jpegData(from: raw) {
                loaded.append(jpeg)
            }
        }
        images = loaded
    }

    @MainActor
    private func post() async {
        isPosting = true
        defer { isPosting = false }
        do {
            let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
            try await services.social.createPost(body: body, type: type, gymId: gymId, images: images)
            onPosted()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
