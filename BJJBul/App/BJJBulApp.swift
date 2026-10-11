import SwiftUI

@main
struct BJJBulApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #if DEBUG
    private let services = DemoMode.isOn ? AppServices.demo : AppServices.live
    #else
    private let services = AppServices.live
    #endif

    var body: some Scene {
        WindowGroup {
            rootView
                .environment(services)
                .task {
                    await services.refreshSession()
                    if isDemo { return }
                    PushManager.shared.services = services
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

    private var isDemo: Bool {
        #if DEBUG
        return DemoMode.isOn
        #else
        return false
        #endif
    }

    @ViewBuilder
    private var rootView: some View {
        #if DEBUG
        if let screen = DemoMode.screen {
            DemoRouter(screen: screen)
        } else {
            RootTabView()
        }
        #else
        RootTabView()
        #endif
    }
}
