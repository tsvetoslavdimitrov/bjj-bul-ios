import UIKit
import UserNotifications

/// Requests permission, registers with APNs and forwards the device token to the backend.
@MainActor
final class PushManager {
    static let shared = PushManager()

    /// Set by BJJBulApp so the token can be stored for the signed-in user.
    var services: AppServices?
    private var pendingToken: String?

    /// APNs environment matching the build's aps-environment entitlement.
    private var environment: String {
        #if DEBUG
        return "development"
        #else
        return "production"
        #endif
    }

    func requestAuthorization() async {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .badge, .sound])) ?? false
        if granted {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    /// Re-register silently when permission was already granted (tokens can change).
    func refreshRegistrationIfAuthorized() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        if settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    func didRegister(deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        pendingToken = token
        Task { await uploadPendingToken() }
    }

    /// Call after sign-in too: tokens are stored per user.
    func uploadPendingToken() async {
        guard let token = pendingToken, let services, services.isSignedIn else { return }
        do {
            try await services.notifications.registerDevice(token: token, environment: environment)
        } catch {
            print("register_device failed: \(error)")
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in
            PushManager.shared.didRegister(deviceToken: deviceToken)
        }
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("APNs registration failed: \(error)")
    }

    /// Show banners while the app is in the foreground.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }
}
