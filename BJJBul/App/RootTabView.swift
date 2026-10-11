import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            FeedView()
                .tabItem { Label("tab.feed", systemImage: "newspaper") }
            ExploreView()
                .tabItem { Label("tab.explore", systemImage: "map") }
            DirectoryView()
                .tabItem { Label("tab.directory", systemImage: "building.2") }
            EventsView()
                .tabItem { Label("tab.events", systemImage: "trophy") }
            ProfileView()
                .tabItem { Label("tab.profile", systemImage: "person.crop.circle") }
        }
    }
}

#Preview {
    RootTabView()
        .environment(AppServices.mock)
}
