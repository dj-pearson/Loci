import UIKit
import UserNotifications

/// US-195: SwiftUI has no `App` hook for the APNs device-token callbacks, so the
/// app needs a `UIApplicationDelegate` bridged in with `@UIApplicationDelegateAdaptor`.
/// Without one, `didRegisterForRemoteNotificationsWithDeviceToken` is never
/// delivered and `users.apns_token` stays null forever.
final class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        PushRegistrationService.shared.handleRegistration(deviceToken: deviceToken)
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        // Deliberately non-fatal: proximity notifications are scheduled locally
        // and keep working without a push token.
        PushRegistrationService.shared.handleRegistrationFailure(error)
    }

    /// Silent pushes used to nudge a background sync. Reporting `.noData` rather
    /// than throwing keeps iOS's background budget intact.
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any]
    ) async -> UIBackgroundFetchResult {
        await PushRegistrationService.shared.syncPendingToken()
        return .noData
    }
}
