import SwiftUI

struct ReviewsSection: View {
    @Environment(AppServices.self) private var services
    let gym: Gym
    @State private var reviews: [GymReview] = []
    @State private var showEditor = false
    @State private var reportTarget: ReportTarget?

    private var myReview: GymReview? {
        guard let uid = services.currentUser?.id else { return nil }
        return reviews.first { $0.userId == uid }
    }

    private var average: Double? {
        guard !reviews.isEmpty else { return nil }
        let total = reviews.map { Double($0.rating) }.reduce(0, +)
        return total / Double(reviews.count)
    }

    var body: some View {
        Section("reviews.title") {
            HStack(spacing: 8) {
                if let average {
                    Text(verbatim: String(format: "%.1f", average))
                        .font(.title2)
                        .bold()
                    VStack(alignment: .leading, spacing: 2) {
                        RatingStarsView(rating: average, size: 14)
                        Text("reviews.count \(reviews.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("reviews.none")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if services.isSignedIn {
                    Button(myReview == nil ? LocalizedStringKey("reviews.write") : LocalizedStringKey("reviews.edit")) {
                        showEditor = true
                    }
                    .buttonStyle(.bordered)
                }
            }

            ForEach(reviews) { review in
                reviewRow(review)
            }
        }
        .task(id: gym.id) {
            await load()
        }
        .sheet(isPresented: $showEditor) {
            ReviewEditorView(gym: gym, existing: myReview) {
                Task { await load() }
            }
        }
        .reportDialog(target: $reportTarget, services: services)
    }

    private func reviewRow(_ review: GymReview) -> some View {
        let isMine = review.userId == services.currentUser?.id
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                if review.authorName.isEmpty {
                    Text("feed.anonymous").font(.subheadline).bold()
                } else {
                    Text(review.authorName).font(.subheadline).bold()
                }
                Spacer()
                RatingStarsView(rating: Double(review.rating))
            }
            if !review.body.isEmpty {
                Text(review.body)
                    .font(.subheadline)
            }
            Text(BGDate.string(review.createdAt, date: .medium, time: .none))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .contextMenu {
            if services.isSignedIn {
                if isMine {
                    Button("reviews.delete", role: .destructive) {
                        Task { await delete(review) }
                    }
                } else {
                    Button("post.report") {
                        reportTarget = ReportTarget(postId: nil, commentId: nil, userId: review.userId,
                                                    reviewId: review.id)
                    }
                }
            }
        }
    }

    @MainActor
    private func load() async {
        reviews = (try? await services.reviews.reviews(gymId: gym.id)) ?? []
    }

    @MainActor
    private func delete(_ review: GymReview) async {
        do {
            try await services.reviews.deleteReview(id: review.id)
            reviews.removeAll { $0.id == review.id }
        } catch {}
    }
}

struct StarPicker: View {
    @Binding var rating: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(1...5, id: \.self) { index in
                Button {
                    rating = index
                } label: {
                    Image(systemName: index <= rating ? "star.fill" : "star")
                        .font(.title2)
                        .foregroundStyle(Color.orange)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: "\(index)"))
            }
        }
    }
}

struct ReviewEditorView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    let gym: Gym
    let existing: GymReview?
    let onSaved: () -> Void
    @State private var rating: Int
    @State private var text: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(gym: Gym, existing: GymReview?, onSaved: @escaping () -> Void) {
        self.gym = gym
        self.existing = existing
        self.onSaved = onSaved
        _rating = State(initialValue: existing?.rating ?? 0)
        _text = State(initialValue: existing?.body ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(gym.name).font(.headline)
                    StarPicker(rating: $rating)
                }
                Section("reviews.text") {
                    TextEditor(text: $text)
                        .frame(minHeight: 140)
                } footer: {
                    Text("reviews.footer")
                }
                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(existing == nil ? LocalizedStringKey("reviews.write") : LocalizedStringKey("reviews.edit"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.save") {
                        Task { await save() }
                    }
                    .disabled(rating == 0 || text.count > 2000 || isSaving)
                }
            }
        }
    }

    @MainActor
    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await services.reviews.saveReview(gymId: gym.id, rating: rating,
                                                  body: text.trimmingCharacters(in: .whitespacesAndNewlines))
            onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
