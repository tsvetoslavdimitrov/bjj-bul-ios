#if DEBUG
import SwiftUI

/// DEBUG-only: opens one screen full-screen for screenshots (`-demo -demoScreen <name>`).
/// Names: see `DemoMode.screenNames`. Unknown names fall back to the normal tab bar.
struct DemoRouter: View {
    @Environment(AppServices.self) private var services
    let screen: String

    var body: some View {
        content
    }

    @ViewBuilder
    private var content: some View {
        switch screen {
        // These screens own their NavigationStack already.
        case "feed": FeedView()
        case "explore": ExploreView()
        case "events": EventsView()
        case "openMats": EventsView(initialSegment: .openMats)
        case "training": TrainingView()
        case "profile": ProfileView()
        case "composer": ComposerView(onPosted: {})
        // Kiosk is its own full-screen UI.
        case "kiosk": KioskView(myGym: DemoData.myGym, waiverText: sampleWaiver) {}
        case "kioskGuest": KioskView(myGym: DemoData.myGym, waiverText: sampleWaiver, initialStep: .guest) {}
        default: NavigationStack { stacked }
        }
    }

    @ViewBuilder
    private var stacked: some View {
        switch screen {
        case "gymDetail": GymDetailView(gym: DemoData.gyms[0])
        case "bjjPass": MyPaymentsView()
        case "myGym": GymDashboardView(myGym: DemoData.myGym)
        case "reports": ReportsView(myGym: DemoData.myGym)
        case "askBJJ": AskBJJView(initialMessages: DemoData.askBJJMessages)
        case "notifications": NotificationsView()
        case "record":
            ScrollView {
                AthleteRecordCard(userId: DemoData.ownerId, smoothcompURL: DemoData.user.smoothcompProfileURL, isMe: true)
                    .padding()
            }
            .navigationTitle("Demo Coach")
        default: RootTabView()
        }
    }

    private var sampleWaiver: String {
        "Sample waiver: I train at my own risk and confirm I am in good health to take part in the class."
    }
}
#endif
