import SwiftUI

struct PostCardView: View {
    let post: Post
    let isMine: Bool
    let canInteract: Bool
    let onLike: () -> Void
    let onDelete: () -> Void
    let onReport: () -> Void
    let onBlock: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if !post.body.isEmpty {
                Text(post.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if !post.mediaURLs.isEmpty {
                photos
            }
            if let music = post.music {
                MusicCardView(music: music)
            }
            if let gymName = post.gymName {
                Label(gymName, systemImage: "mappin.and.ellipse")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            actions
        }
        .padding()
    }

    private var header: some View {
        HStack(spacing: 10) {
            NavigationLink(value: UserRoute(id: post.authorId)) {
                HStack(spacing: 10) {
                    CoachPhotoView(url: post.authorAvatarURL, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        if post.authorName.isEmpty {
                            Text("feed.anonymous").font(.subheadline).bold()
                        } else {
                            Text(post.authorName).font(.subheadline).bold()
                        }
                        HStack(spacing: 4) {
                            if let belt = post.authorBelt {
                                Text(LocalizedStringKey(belt.localizedKey))
                                Text(verbatim: "·")
                            }
                            Text(post.createdAt.formatted(.relative(presentation: .named)))
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer()

            Text(LocalizedStringKey(post.type.localizedKey))
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.accentColor.opacity(0.15)))

            if canInteract {
                Menu {
                    if isMine {
                        Button("post.delete", role: .destructive, action: onDelete)
                    } else {
                        Button("post.report", action: onReport)
                        Button("user.block", role: .destructive, action: onBlock)
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .padding(8)
                }
                .accessibilityLabel(Text("post.more"))
            }
        }
    }

    private var photos: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(post.mediaURLs, id: \.self) { url in
                    if Post.isVideoURL(url) {
                        PostVideoView(url: url)
                            .frame(width: post.mediaURLs.count == 1 ? 320 : 240, height: 320)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        AsyncImage(url: url) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            Rectangle().fill(Color.secondary.opacity(0.15))
                        }
                        .frame(width: post.mediaURLs.count == 1 ? 320 : 240, height: 240)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 24) {
            Button(action: onLike) {
                Label {
                    Text(verbatim: "\(post.likeCount)")
                } icon: {
                    Image(systemName: post.likedByMe ? "heart.fill" : "heart")
                        .foregroundStyle(post.likedByMe ? Color.red : Color.primary)
                }
            }
            .buttonStyle(.plain)
            .disabled(!canInteract)
            .accessibilityLabel(Text("post.like"))

            NavigationLink(value: post) {
                Label {
                    Text(verbatim: "\(post.commentCount)")
                } icon: {
                    Image(systemName: "bubble.right")
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("post.comments"))

            Spacer()
        }
        .font(.subheadline)
    }
}
