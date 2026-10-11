import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            FeedView()
                .tabItem { Label("tab.feed", systemImage: "newspaper") }
            ExploreView()
                .tabItem { Label("tab.explore", systemImage: "map") }
            EventsView()
                .tabItem { Label("tab.events", systemImage: "trophy") }
            TrainingView()
                .tabItem { Label("tab.training", systemImage: "figure.martial.arts") }
            ProfileView()
                .tabItem { Label("tab.profile", systemImage: "person.crop.circle") }
        }
    }
}

#Preview {
    RootTabView()
        .environment(AppServices.mock)
}
