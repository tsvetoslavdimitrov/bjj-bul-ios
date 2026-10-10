import SwiftUI

@main
struct BJJBulApp: App {
    private let services = AppServices.live

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(services)
                .task { await services.refreshSession() }
        }
    }
}
