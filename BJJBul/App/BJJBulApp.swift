import SwiftUI

@main
struct BJJBulApp: App {
    private let services = AppServices.live

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(services)
                .task { await services.refreshSession() }
                .fullScreenCover(isPresented: Binding(
                    get: { services.needsTermsAcceptance },
                    set: { _ in }
                )) {
                    TermsAcceptanceView()
                        .environment(services)
                }
        }
    }
}
