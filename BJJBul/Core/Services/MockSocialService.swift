import Foundation

final class MockSocialService: SocialService {
    private var posts: [Post]
    private var commentsByPost: [UUID: [PostComment]] = [:]
    private var following: Set<UUID> = []
    private var blocked: Set<UUID> = []
    private let otherUserId = UUID(uuidString: "00000000-0000-0000-0000-000000000301")!

    init() {
        let now = Date()
        posts = [
            Post(id: UUID(), authorId: otherUserId, authorName: "Георги", authorAvatarURL: nil,
                 authorBelt: .purple, body: "Първа лилава лента! 🙏", type: .promotion,
                 gymId: MockData.gym1Id, gymName: MockData.gyms[0].name,
                 createdAt: now.addingTimeInterval(-3600), cursor: "2026-01-01T10:00:00+00:00",
                 mediaURLs: [], likeCount: 12, commentCount: 1, likedByMe: false),
            Post(id: UUID(), authorId: MockData.user.id, authorName: MockData.user.displayName,
                 authorAvatarURL: nil, authorBelt: MockData.user.belt,
                 body: "Great open mat today.", type: .training, gymId: nil, gymName: nil,
                 createdAt: now.addingTimeInterval(-7200), cursor: "2026-01-01T09:00:00+00:00",
                 mediaURLs: [], likeCount: 3, commentCount: 0, likedByMe: true)
        ]
    }

    func feed(scope: FeedScope, authorId: UUID?, before: String?, limit: Int) async throws -> [Post] {
        if before != nil { return [] }
        return posts.filter { post in
            if blocked.contains(post.authorId) { return false }
            if let authorId, post.authorId != authorId { return false }
            if scope == .following {
                return post.authorId == MockData.user.id || following.contains(post.authorId)
            }
            return true
        }
    }

    func createPost(body: String, type: PostType, gymId: UUID?, media: [ComposerMedia],
                    music: MusicAttachment?) async throws {
        let post = Post(id: UUID(), authorId: MockData.user.id, authorName: MockData.user.displayName,
                        authorAvatarURL: nil, authorBelt: MockData.user.belt, body: body, type: type,
                        gymId: gymId, gymName: nil, createdAt: Date(), cursor: "2026-01-02T00:00:00+00:00",
                        mediaURLs: [], likeCount: 0, commentCount: 0, likedByMe: false, music: music)
        posts.insert(post, at: 0)
    }

    func deletePost(id: UUID) async throws {
        posts.removeAll { $0.id == id }
    }

    func setLike(postId: UUID, liked: Bool) async throws {}

    func comments(postId: UUID) async throws -> [PostComment] {
        commentsByPost[postId] ?? []
    }

    func addComment(postId: UUID, body: String) async throws {
        let comment = PostComment(id: UUID(), postId: postId, authorId: MockData.user.id,
                                  authorName: MockData.user.displayName, authorAvatarURL: nil,
                                  body: body, createdAt: Date())
        commentsByPost[postId, default: []].append(comment)
    }

    func deleteComment(id: UUID) async throws {
        for key in commentsByPost.keys {
            commentsByPost[key]?.removeAll { $0.id == id }
        }
    }

    func profile(userId: UUID) async throws -> PublicProfile? {
        let isMe = userId == MockData.user.id
        return PublicProfile(id: userId, displayName: isMe ? MockData.user.displayName : "Георги",
                             avatarURL: nil, belt: isMe ? MockData.user.belt : .purple, stripes: 1,
                             homeGymId: MockData.gym1Id, followerCount: 5, followingCount: 3,
                             postCount: posts.filter { $0.authorId == userId }.count,
                             followedByMe: following.contains(userId), blocked: blocked.contains(userId))
    }

    func setFollow(userId: UUID, following isFollowing: Bool) async throws {
        if isFollowing {
            following.insert(userId)
        } else {
            following.remove(userId)
        }
    }

    func report(_ target: ReportTarget, reason: ReportReason) async throws {}

    func block(userId: UUID) async throws {
        blocked.insert(userId)
        following.remove(userId)
    }
}
