import SwiftUI

@main
struct BJJBulApp: App {
    private let services = AppServices.mock

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(services)
        }
    }
}
