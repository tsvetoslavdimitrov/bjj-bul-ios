import SwiftUI

struct CommentsView: View {
    @Environment(AppServices.self) private var services
    let post: Post
    @State private var comments: [PostComment] = []
    @State private var draft = ""
    @State private var isSending = false
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var reportTarget: ReportTarget?

    var body: some View {
        List {
            Section {
                if !post.body.isEmpty {
                    Text(post.body)
                }
            } header: {
                Text(post.authorName)
            }

            Section("post.comments") {
                if comments.isEmpty && !isLoading {
                    Text("comments.empty").foregroundStyle(.secondary)
                }
                ForEach(comments) { comment in
                    commentRow(comment)
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("post.comments")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await load()
        }
        .task {
            await load()
        }
        .safeAreaInset(edge: .bottom) {
            inputBar
        }
        .reportDialog(target: $reportTarget, services: services)
    }

    private func commentRow(_ comment: PostComment) -> some View {
        let isMine = comment.authorId == services.currentUser?.id
        return NavigationLink(value: UserRoute(id: comment.authorId)) {
            HStack(alignment: .top, spacing: 10) {
                CoachPhotoView(url: comment.authorAvatarURL, size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        if comment.authorName.isEmpty {
                            Text("feed.anonymous").font(.subheadline).bold()
                        } else {
                            Text(comment.authorName).font(.subheadline).bold()
                        }
                        Text(comment.createdAt.formatted(.relative(presentation: .named)))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(comment.body)
                }
            }
        }
        .contextMenu {
            if services.isSignedIn {
                if isMine {
                    Button("comments.delete", role: .destructive) {
                        Task { await delete(comment) }
                    }
                } else {
                    Button("post.report") {
                        reportTarget = ReportTarget(postId: nil, commentId: comment.id, userId: comment.authorId)
                    }
                }
            }
        }
        .swipeActions {
            if isMine {
                Button("comments.delete", role: .destructive) {
                    Task { await delete(comment) }
                }
            }
        }
    }

    @ViewBuilder
    private var inputBar: some View {
        if services.isSignedIn {
            HStack {
                TextField("comments.placeholder", text: $draft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                Button {
                    Task { await send() }
                } label: {
                    Image(systemName: "paperplane.fill")
                }
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
                .accessibilityLabel(Text("comments.send"))
            }
            .padding()
            .background(.bar)
        } else {
            Text("comments.signIn")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding()
                .background(.bar)
        }
    }

    @MainActor
    private func load() async {
        defer { isLoading = false }
        do {
            comments = try await services.social.comments(postId: post.id)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func send() async {
        let body = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        isSending = true
        defer { isSending = false }
        do {
            try await services.social.addComment(postId: post.id, body: String(body.prefix(1000)))
            draft = ""
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func delete(_ comment: PostComment) async {
        do {
            try await services.social.deleteComment(id: comment.id)
            comments.removeAll { $0.id == comment.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
