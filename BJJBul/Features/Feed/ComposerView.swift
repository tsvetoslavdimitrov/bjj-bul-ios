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
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var videoItem: PhotosPickerItem?
    @State private var media: [ComposerMedia] = []
    @State private var isProcessing = false
    @State private var isPosting = false
    @State private var showCamera = false
    @State private var musicText = ""
    @State private var music: MusicAttachment?
    @State private var isLoadingMusic = false
    @State private var errorMessage: String?

    private let maxMedia = 4
    private let maxLength = 2000

    private var hasVideo: Bool { media.contains { $0.kind == .video } }
    private var remainingSlots: Int { max(0, maxMedia - media.count) }

    private var canPost: Bool {
        let hasText = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return (hasText || !media.isEmpty || music != nil) && text.count <= maxLength
            && !isPosting && !isProcessing && !isLoadingMusic
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

                Section {
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
                } header: {
                    Text("composer.details")
                }

                mediaSection
                musicSection

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
            .onChange(of: photoItems) { _, newItems in
                guard !newItems.isEmpty else { return }
                Task { await addPhotos(newItems) }
            }
            .onChange(of: videoItem) { _, newItem in
                guard let newItem else { return }
                Task { await addLibraryVideo(newItem) }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { result in
                    showCamera = false
                    if let result {
                        Task { await handleCamera(result) }
                    }
                }
                .ignoresSafeArea()
            }
            .task {
                gyms = (try? await services.gyms.gyms(cityId: nil)) ?? []
                if let home = services.currentUser?.homeGymId {
                    gymId = home
                }
            }
        }
    }

    private var mediaSection: some View {
        Section {
            if CameraPicker.isAvailable {
                Button {
                    showCamera = true
                } label: {
                    Label("composer.camera", systemImage: "camera")
                }
                .disabled(remainingSlots == 0)
            }
            PhotosPicker(selection: $photoItems, maxSelectionCount: max(1, remainingSlots), matching: .images) {
                Label("composer.addPhotos", systemImage: "photo.on.rectangle")
            }
            .disabled(remainingSlots == 0)
            PhotosPicker(selection: $videoItem, matching: .videos) {
                Label("composer.addVideo", systemImage: "video")
            }
            .disabled(remainingSlots == 0 || hasVideo)
            if isProcessing {
                HStack {
                    ProgressView()
                    Text("composer.processing").font(.footnote).foregroundStyle(.secondary)
                }
            }
            if !media.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(media) { item in
                            thumbnail(item)
                        }
                    }
                }
            }
        } header: {
            Text("composer.media")
        } footer: {
            Text("composer.media.footer")
        }
    }

    private func thumbnail(_ item: ComposerMedia) -> some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let preview = item.thumbnail ?? (item.kind == .image ? item.data : nil),
                   let uiImage = UIImage(data: preview) {
                    Image(uiImage: uiImage).resizable().scaledToFill()
                } else {
                    Color.secondary.opacity(0.2)
                }
            }
            .frame(width: 80, height: 80)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                if item.kind == .video {
                    Image(systemName: "play.circle.fill")
                        .font(.title)
                        .foregroundStyle(.white)
                        .shadow(radius: 2)
                }
            }
            Button {
                media.removeAll { $0.id == item.id }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.white, .black.opacity(0.6))
            }
            .buttonStyle(.borderless)
            .padding(2)
        }
    }

    private var musicSection: some View {
        Section {
            HStack {
                TextField("composer.music.placeholder", text: $musicText)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit {
                        Task { await loadMusic() }
                    }
                if isLoadingMusic {
                    ProgressView()
                } else {
                    Button("composer.music.attach") {
                        Task { await loadMusic() }
                    }
                    .disabled(musicText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            if let music {
                MusicCardView(music: music)
                Button("composer.music.remove", role: .destructive) {
                    self.music = nil
                    musicText = ""
                }
            }
        } header: {
            Text("composer.music")
        } footer: {
            Text("composer.music.footer")
        }
    }

    // MARK: - Loading media

    @MainActor
    private func addPhotos(_ items: [PhotosPickerItem]) async {
        isProcessing = true
        defer {
            isProcessing = false
            photoItems = []
        }
        for item in items.prefix(remainingSlots) {
            if let raw = try? await item.loadTransferable(type: Data.self),
               let jpeg = ImageCompressor.jpegData(from: raw) {
                media.append(ComposerMedia(kind: .image, data: jpeg, thumbnail: nil))
            }
        }
    }

    @MainActor
    private func addLibraryVideo(_ item: PhotosPickerItem) async {
        isProcessing = true
        defer {
            isProcessing = false
            videoItem = nil
        }
        do {
            guard let movie = try await item.loadTransferable(type: PickedMovie.self) else { return }
            try await addVideo(at: movie.url)
            try? FileManager.default.removeItem(at: movie.url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func handleCamera(_ result: CameraPicker.Result) async {
        guard remainingSlots > 0 else { return }
        isProcessing = true
        defer { isProcessing = false }
        switch result {
        case .image(let image):
            if let raw = image.jpegData(compressionQuality: 0.9), let jpeg = ImageCompressor.jpegData(from: raw) {
                media.append(ComposerMedia(kind: .image, data: jpeg, thumbnail: nil))
            }
        case .movie(let url):
            if hasVideo {
                errorMessage = String(localized: "composer.video.onlyOne")
                return
            }
            do {
                try await addVideo(at: url)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    @MainActor
    private func addVideo(at url: URL) async throws {
        let thumb = await VideoTools.thumbnail(url)
        let data = try await VideoTools.compress(url)
        media.append(ComposerMedia(kind: .video, data: data, thumbnail: thumb))
    }

    @MainActor
    private func loadMusic() async {
        guard let url = MusicLink.extract(from: musicText) else {
            errorMessage = String(localized: "composer.music.unsupported")
            return
        }
        isLoadingMusic = true
        defer { isLoadingMusic = false }
        music = await MusicLink.fetchMetadata(for: url)
        errorMessage = nil
    }

    @MainActor
    private func post() async {
        isPosting = true
        defer { isPosting = false }
        do {
            let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
            try await services.social.createPost(body: body, type: type, gymId: gymId, media: media, music: music)
            onPosted()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
