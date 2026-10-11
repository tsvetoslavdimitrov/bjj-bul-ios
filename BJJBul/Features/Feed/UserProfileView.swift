import SwiftUI

struct UserProfileView: View {
    @Environment(AppServices.self) private var services
    let userId: UUID
    @State private var profile: PublicProfile?
    @State private var homeGym: Gym?
    @State private var reportTarget: ReportTarget?
    @State private var confirmBlock = false
    @State private var isBlocked = false
    @State private var errorMessage: String?

    private var isMe: Bool { services.currentUser?.id == userId }

    var body: some View {
        Group {
            if isBlocked {
                ContentUnavailableView("user.blocked", systemImage: "hand.raised")
            } else {
                PostListView(reloadKey: userId.uuidString) { before in
                    try await services.social.feed(scope: .all, authorId: userId, before: before, limit: 20)
                } header: {
                    header
                }
            }
        }
        .navigationTitle(profile?.displayName ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if services.isSignedIn && !isMe {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("user.report") {
                            reportTarget = ReportTarget(postId: nil, commentId: nil, userId: userId)
                        }
                        Button("user.block", role: .destructive) {
                            confirmBlock = true
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .task {
            await loadProfile()
        }
        .reportDialog(target: $reportTarget, services: services)
        .confirmationDialog("user.block.confirmTitle", isPresented: $confirmBlock, titleVisibility: .visible) {
            Button("user.block", role: .destructive) {
                Task { await block() }
            }
            Button("common.cancel", role: .cancel) {}
        } message: {
            Text("user.block.message")
        }
    }

    @ViewBuilder
    private var header: some View {
        if let profile {
            VStack(spacing: 10) {
                CoachPhotoView(url: profile.avatarURL, size: 80)
                if profile.displayName.isEmpty {
                    Text("feed.anonymous").font(.title3).bold()
                } else {
                    Text(profile.displayName).font(.title3).bold()
                }
                HStack(spacing: 4) {
                    Text(LocalizedStringKey(profile.belt.localizedKey))
                    Text(verbatim: "·")
                    Text("profile.stripes \(profile.stripes)")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                if let homeGym {
                    NavigationLink(value: homeGym) {
                        Label(homeGym.name, systemImage: "building.2")
                            .font(.footnote)
                    }
                }
                if let team = profile.team, !team.isEmpty {
                    Label(team, systemImage: "shield")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 24) {
                    stat(profile.postCount, key: "user.posts")
                    stat(profile.followerCount, key: "user.followers")
                    stat(profile.followingCount, key: "user.following")
                }
                if services.isSignedIn && !isMe {
                    Button {
                        Task { await toggleFollow() }
                    } label: {
                        if profile.followedByMe {
                            Text("user.unfollow").frame(minWidth: 140)
                        } else {
                            Text("user.follow").frame(minWidth: 140)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(profile.followedByMe ? Color.secondary : Color.accentColor)
                }
                if let errorMessage {
                    Text(errorMessage).font(.footnote).foregroundStyle(.red)
                }
                AthleteRecordCard(userId: profile.id, smoothcompURL: profile.smoothcompProfileURL, isMe: isMe)
            }
            .padding()
            .frame(maxWidth: .infinity)
        } else {
            ProgressView().padding()
        }
    }

    private func stat(_ value: Int, key: LocalizedStringKey) -> some View {
        VStack {
            Text(verbatim: "\(value)").font(.headline)
            Text(key).font(.caption).foregroundStyle(.secondary)
        }
    }

    @MainActor
    private func loadProfile() async {
        do {
            profile = try await services.social.profile(userId: userId)
            isBlocked = profile?.blocked ?? false
            if let gymId = profile?.homeGymId {
                homeGym = try? await services.gyms.gym(id: gymId)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func toggleFollow() async {
        guard var current = profile else { return }
        let newValue = !current.followedByMe
        current.followedByMe = newValue
        current.followerCount += newValue ? 1 : -1
        profile = current
        do {
            try await services.social.setFollow(userId: userId, following: newValue)
        } catch {
            errorMessage = error.localizedDescription
            await loadProfile()
        }
    }

    @MainActor
    private func block() async {
        do {
            try await services.social.block(userId: userId)
            isBlocked = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
