import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            FeedView()
                .tabItem { Label("tab.feed", systemImage: "newspaper") }
            ExploreView()
                .tabItem { Label("tab.explore", systemImage: "map") }
            GymListView()
                .tabItem { Label("tab.gyms", systemImage: "building.2") }
            CoachListView()
                .tabItem { Label("tab.coaches", systemImage: "person.2") }
            ProfileView()
                .tabItem { Label("tab.profile", systemImage: "person.crop.circle") }
        }
    }
}

#Preview {
    RootTabView()
        .environment(AppServices.mock)
}
