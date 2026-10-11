import SwiftUI

@main
struct BJJBulApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let services = AppServices.live

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(services)
                .task {
                    PushManager.shared.services = services
                    await services.refreshSession()
                    await PushManager.shared.refreshRegistrationIfAuthorized()
                }
                .onChange(of: services.isSignedIn) { _, signedIn in
                    if signedIn {
                        Task { await PushManager.shared.uploadPendingToken() }
                    }
                }
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
