import Foundation
import Supabase

struct SupabaseSocialService: SocialService {
    let client: SupabaseClient
    private let bucket = "post-media"

    private func userId() async throws -> UUID {
        let session = try await client.auth.session
        return session.user.id
    }

    private func publicURL(_ path: String) -> URL? {
        try? client.storage.from(bucket).getPublicURL(path: path)
    }

    func feed(scope: FeedScope, authorId: UUID?, before: String?, limit: Int) async throws -> [Post] {
        let params = FeedParams(p_scope: scope.rawValue, p_author: authorId, p_before: before, p_limit: limit)
        let rows: [PostRow] = try await client.rpc("get_feed", params: params)
            .execute()
            .value
        return rows.map { row -> Post in
            var post = row.toModel(mediaURLs: row.media_paths.compactMap { publicURL($0) })
            if let link = row.music_url, let url = URL(string: link) {
                post.music = MusicAttachment(url: url, title: row.music_title, artist: row.music_artist,
                                             artworkURL: row.music_artwork.flatMap { URL(string: $0) })
            }
            return post
        }
    }

    func createPost(body: String, type: PostType, gymId: UUID?, media: [ComposerMedia],
                    music: MusicAttachment?) async throws {
        let uid = try await userId()
        let insert = PostInsert(author_id: uid, body: body, type: type.rawValue, gym_id: gymId)
        let created: IdRow = try await client.from("posts")
            .insert(insert)
            .select("id")
            .single()
            .execute()
            .value
        if let music {
            // Separate update so posting still works before migration 0010 (music is then dropped).
            let update = MusicUpdate(music_url: music.url.absoluteString, music_title: music.title,
                                     music_artist: music.artist, music_artwork: music.artworkURL?.absoluteString)
            try? await client.from("posts").update(update).eq("id", value: created.id.uuidString).execute()
        }
        // Storage policy requires the first folder to be the user's id (lowercase).
        let folder = "\(uid.uuidString.lowercased())/\(created.id.uuidString.lowercased())"
        for (index, item) in media.prefix(4).enumerated() {
            let isVideo = item.kind == .video
            let path = "\(folder)/\(index).\(isVideo ? "mp4" : "jpg")"
            _ = try await client.storage.from(bucket)
                .upload(path, data: item.data,
                        options: FileOptions(contentType: isVideo ? "video/mp4" : "image/jpeg"))
            if isVideo {
                try await client.from("post_media")
                    .insert(MediaKindInsert(post_id: created.id, storage_path: path, position: index, kind: "video"))
                    .execute()
            } else {
                try await client.from("post_media")
                    .insert(MediaInsert(post_id: created.id, storage_path: path, position: index))
                    .execute()
            }
        }
    }

    func deletePost(id: UUID) async throws {
        let media: [MediaPathRow] = (try? await client.from("post_media")
            .select("storage_path")
            .eq("post_id", value: id.uuidString)
            .execute()
            .value) ?? []
        try await client.from("posts")
            .delete()
            .eq("id", value: id.uuidString)
            .execute()
        let paths = media.map { $0.storage_path }
        if !paths.isEmpty {
            _ = try? await client.storage.from(bucket).remove(paths: paths)
        }
    }

    func setLike(postId: UUID, liked: Bool) async throws {
        let uid = try await userId()
        if liked {
            try await client.from("likes")
                .upsert(LikeRow(post_id: postId, user_id: uid), onConflict: "post_id,user_id")
                .execute()
        } else {
            try await client.from("likes")
                .delete()
                .eq("post_id", value: postId.uuidString)
                .eq("user_id", value: uid.uuidString)
                .execute()
        }
    }

    func comments(postId: UUID) async throws -> [PostComment] {
        let rows: [CommentRow] = try await client.rpc("get_comments", params: CommentsParams(p_post: postId))
            .execute()
            .value
        return rows.map { $0.toModel() }
    }

    func addComment(postId: UUID, body: String) async throws {
        let uid = try await userId()
        try await client.from("comments")
            .insert(CommentInsert(post_id: postId, author_id: uid, body: body))
            .execute()
    }

    func deleteComment(id: UUID) async throws {
        try await client.from("comments")
            .delete()
            .eq("id", value: id.uuidString)
            .execute()
    }

    func profile(userId: UUID) async throws -> PublicProfile? {
        let rows: [PublicProfileRow] = try await client.rpc("get_public_profile", params: ProfileParams(p_user: userId))
            .execute()
            .value
        return rows.first?.toModel()
    }

    func setFollow(userId target: UUID, following: Bool) async throws {
        let uid = try await userId()
        if following {
            try await client.from("follows")
                .upsert(FollowRow(follower_id: uid, followee_id: target), onConflict: "follower_id,followee_id")
                .execute()
        } else {
            try await client.from("follows")
                .delete()
                .eq("follower_id", value: uid.uuidString)
                .eq("followee_id", value: target.uuidString)
                .execute()
        }
    }

    func report(_ target: ReportTarget, reason: ReportReason) async throws {
        let uid = try await userId()
        let row = ReportInsert(reporter_id: uid, post_id: target.postId, comment_id: target.commentId,
                               reported_user_id: target.userId, review_id: target.reviewId,
                               reason: reason.rawValue)
        try await client.from("reports")
            .insert(row)
            .execute()
    }

    func block(userId target: UUID) async throws {
        let uid = try await userId()
        try await client.from("blocks")
            .upsert(BlockRow(blocker_id: uid, blocked_id: target), onConflict: "blocker_id,blocked_id")
            .execute()
        // Also stop following them.
        try? await client.from("follows")
            .delete()
            .eq("follower_id", value: uid.uuidString)
            .eq("followee_id", value: target.uuidString)
            .execute()
    }
}

// MARK: - DTOs

struct FeedParams: Encodable {
    let p_scope: String
    let p_author: UUID?
    let p_before: String?
    let p_limit: Int
}

struct CommentsParams: Encodable {
    let p_post: UUID
}

struct ProfileParams: Encodable {
    let p_user: UUID
}

struct IdRow: Decodable {
    let id: UUID
}

struct MediaPathRow: Decodable {
    let storage_path: String
}

struct PostInsert: Encodable {
    let author_id: UUID
    let body: String
    let type: String
    let gym_id: UUID?
}

struct MediaInsert: Encodable {
    let post_id: UUID
    let storage_path: String
    let position: Int
}

struct LikeRow: Codable {
    let post_id: UUID
    let user_id: UUID
}

struct FollowRow: Codable {
    let follower_id: UUID
    let followee_id: UUID
}

struct BlockRow: Codable {
    let blocker_id: UUID
    let blocked_id: UUID
}

struct CommentInsert: Encodable {
    let post_id: UUID
    let author_id: UUID
    let body: String
}

struct ReportInsert: Encodable {
    let reporter_id: UUID
    let post_id: UUID?
    let comment_id: UUID?
    let reported_user_id: UUID?
    let review_id: UUID?
    let reason: String
}

struct PostRow: Decodable {
    let id: UUID
    let author_id: UUID
    let author_name: String?
    let author_avatar: String?
    let author_belt: String?
    let body: String
    let type: String
    let gym_id: UUID?
    let gym_name: String?
    let created_at: String
    let media_paths: [String]
    let like_count: Int
    let comment_count: Int
    let liked_by_me: Bool
    // 0010 (absent before the migration)
    let music_url: String?
    let music_title: String?
    let music_artist: String?
    let music_artwork: String?

    func toModel(mediaURLs: [URL]) -> Post {
        Post(id: id, authorId: author_id, authorName: author_name ?? "",
             authorAvatarURL: author_avatar.flatMap { URL(string: $0) },
             authorBelt: author_belt.flatMap { Belt(rawValue: $0) },
             body: body, type: PostType(rawValue: type) ?? .progress,
             gymId: gym_id, gymName: gym_name,
             createdAt: DateParsing.date(from: created_at), cursor: created_at,
             mediaURLs: mediaURLs, likeCount: like_count, commentCount: comment_count,
             likedByMe: liked_by_me)
    }
}

struct CommentRow: Decodable {
    let id: UUID
    let post_id: UUID
    let author_id: UUID
    let author_name: String?
    let author_avatar: String?
    let body: String
    let created_at: String

    func toModel() -> PostComment {
        PostComment(id: id, postId: post_id, authorId: author_id, authorName: author_name ?? "",
                    authorAvatarURL: author_avatar.flatMap { URL(string: $0) },
                    body: body, createdAt: DateParsing.date(from: created_at))
    }
}

struct PublicProfileRow: Decodable {
    let id: UUID
    let display_name: String?
    let avatar_url: String?
    let belt: String?
    let stripes: Int?
    let home_gym_id: UUID?
    let follower_count: Int
    let following_count: Int
    let post_count: Int
    let followed_by_me: Bool
    let blocked: Bool
    let team: String?
    let team_gym_id: UUID?
    let smoothcomp_profile_url: String?

    func toModel() -> PublicProfile {
        PublicProfile(id: id, displayName: display_name ?? "",
                      avatarURL: avatar_url.flatMap { URL(string: $0) },
                      belt: belt.flatMap { Belt(rawValue: $0) } ?? .white,
                      stripes: stripes ?? 0, homeGymId: home_gym_id,
                      followerCount: follower_count, followingCount: following_count,
                      postCount: post_count, followedByMe: followed_by_me, blocked: blocked,
                      team: team, teamGymId: team_gym_id,
                      smoothcompProfileURL: smoothcomp_profile_url.flatMap { URL(string: $0) })
    }
}

struct MediaKindInsert: Encodable {
    let post_id: UUID
    let storage_path: String
    let position: Int
    let kind: String
}

struct MusicUpdate: Encodable {
    let music_url: String
    let music_title: String?
    let music_artist: String?
    let music_artwork: String?
}
