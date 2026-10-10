import SwiftUI

/// Scrollable, paginated list of posts with like / delete / report / block handling.
struct PostListView<Header: View>: View {
    @Environment(AppServices.self) private var services
    /// Changing this reloads from the first page.
    let reloadKey: String
    let load: (_ before: String?) async throws -> [Post]
    @ViewBuilder let header: () -> Header

    @State private var posts: [Post] = []
    @State private var isLoading = false
    @State private var reachedEnd = false
    @State private var errorMessage: String?
    @State private var reportTarget: ReportTarget?
    @State private var blockTarget: UUID?
    @State private var deleteTarget: UUID?

    private let pageSize = 20

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                header()
                if posts.isEmpty && !isLoading {
                    ContentUnavailableView("feed.empty", systemImage: "text.bubble")
                        .padding(.top, 40)
                }
                ForEach(posts) { post in
                    PostCardView(
                        post: post,
                        isMine: post.authorId == services.currentUser?.id,
                        canInteract: services.isSignedIn,
                        onLike: { Task { await toggleLike(post) } },
                        onDelete: { deleteTarget = post.id },
                        onReport: { reportTarget = ReportTarget(postId: post.id, commentId: nil, userId: post.authorId) },
                        onBlock: { blockTarget = post.authorId }
                    )
                    .onAppear {
                        if post.id == posts.last?.id {
                            Task { await loadMore() }
                        }
                    }
                    Divider()
                }
                if isLoading {
                    ProgressView().padding()
                }
                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding()
                }
            }
        }
        .refreshable {
            await reload()
        }
        .task(id: reloadKey) {
            await reload()
        }
        .reportDialog(target: $reportTarget, services: services)
        .confirmationDialog("user.block.confirmTitle", isPresented: Binding(
            get: { blockTarget != nil },
            set: { if !$0 { blockTarget = nil } }
        ), titleVisibility: .visible) {
            Button("user.block", role: .destructive) {
                if let id = blockTarget {
                    Task { await block(id) }
                }
            }
            Button("common.cancel", role: .cancel) {}
        } message: {
            Text("user.block.message")
        }
        .confirmationDialog("post.delete.confirmTitle", isPresented: Binding(
            get: { deleteTarget != nil },
            set: { if !$0 { deleteTarget = nil } }
        ), titleVisibility: .visible) {
            Button("post.delete", role: .destructive) {
                if let id = deleteTarget {
                    Task { await delete(id) }
                }
            }
            Button("common.cancel", role: .cancel) {}
        }
    }

    @MainActor
    func reload() async {
        reachedEnd = false
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await load(nil)
            posts = page
            reachedEnd = page.count < pageSize
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func loadMore() async {
        guard !isLoading, !reachedEnd, let cursor = posts.last?.cursor else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await load(cursor)
            let existing = Set(posts.map { $0.id })
            posts.append(contentsOf: page.filter { !existing.contains($0.id) })
            reachedEnd = page.count < pageSize
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func toggleLike(_ post: Post) async {
        guard services.isSignedIn, let index = posts.firstIndex(where: { $0.id == post.id }) else { return }
        let newValue = !posts[index].likedByMe
        posts[index].likedByMe = newValue
        posts[index].likeCount += newValue ? 1 : -1
        do {
            try await services.social.setLike(postId: post.id, liked: newValue)
        } catch {
            if let i = posts.firstIndex(where: { $0.id == post.id }) {
                posts[i].likedByMe = !newValue
                posts[i].likeCount += newValue ? -1 : 1
            }
        }
    }

    @MainActor
    private func delete(_ id: UUID) async {
        do {
            try await services.social.deletePost(id: id)
            posts.removeAll { $0.id == id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func block(_ userId: UUID) async {
        do {
            try await services.social.block(userId: userId)
            // Hide their content immediately.
            posts.removeAll { $0.authorId == userId }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
