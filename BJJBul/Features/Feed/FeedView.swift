import SwiftUI

struct FeedView: View {
    @Environment(AppServices.self) private var services
    @State private var scope: FeedScope = .all
    @State private var showComposer = false
    @State private var refreshToken = UUID()
    @State private var quotes: [Quote] = []

    var body: some View {
        NavigationStack {
            PostListView(reloadKey: "\(scope.rawValue)-\(refreshToken.uuidString)-\(services.isSignedIn)",
                         quotes: quotes) { before in
                try await services.social.feed(scope: scope, authorId: nil, before: before, limit: 20)
            } header: {
                VStack(spacing: 12) {
                    if let quote = QuotePicker.quoteOfTheDay(quotes) {
                        QuoteCardView(quote: quote, isQuoteOfTheDay: true)
                    }
                    Picker("feed.scope", selection: $scope) {
                        ForEach(FeedScope.allCases, id: \.self) { item in
                            Text(LocalizedStringKey(item.localizedKey)).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    if scope == .following && !services.isSignedIn {
                        Text("feed.following.signIn")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
            .navigationTitle("tab.feed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Image("Logo")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 28)
                        .accessibilityLabel(Text(verbatim: "BJJ Bul"))
                }
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        NotificationsView()
                    } label: {
                        Image(systemName: "bell")
                    }
                    .accessibilityLabel(Text("notifications.title"))
                }
                if services.isSignedIn {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showComposer = true
                        } label: {
                            Image(systemName: "square.and.pencil")
                        }
                        .accessibilityLabel(Text("composer.title"))
                    }
                }
            }
            .sheet(isPresented: $showComposer) {
                ComposerView {
                    refreshToken = UUID()
                }
            }
            .task {
                if quotes.isEmpty {
                    quotes = (try? await services.quotes.quotes()) ?? MockQuoteData.quotes
                }
            }
            .navigationDestination(for: UserRoute.self) { route in
                UserProfileView(userId: route.id)
            }
            .navigationDestination(for: Post.self) { post in
                CommentsView(post: post)
            }
            .navigationDestination(for: Gym.self) { gym in
                GymDetailView(gym: gym)
            }
            .navigationDestination(for: Coach.self) { coach in
                CoachDetailView(coach: coach)
            }
        }
    }
}
