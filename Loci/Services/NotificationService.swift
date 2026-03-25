import Foundation
import UserNotifications

@Observable
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    // MARK: - Properties

    private(set) var isAuthorized = false
    private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private let notificationCenter: UNUserNotificationCenter

    // MARK: - Notification Categories & Actions

    static let viewLocusActionIdentifier = "VIEW_LOCUS"
    static let addNoteActionIdentifier = "ADD_NOTE"
    static let archiveActionIdentifier = "ARCHIVE"
    static let locusCategoryIdentifier = "LOCUS_PROXIMITY"

    // MARK: - Initialization

    override init() {
        notificationCenter = UNUserNotificationCenter.current()
        super.init()
        notificationCenter.delegate = self
        configureCategories()

        Task {
            await checkAuthorizationStatus()
        }
    }

    // MARK: - Permission Management

    /// Requests notification permissions for alerts, sounds, and badges.
    /// Returns `true` if the user granted permission.
    @discardableResult
    func requestPermission() async -> Bool {
        do {
            let granted = try await notificationCenter.requestAuthorization(
                options: [.alert, .sound, .badge]
            )
            await checkAuthorizationStatus()
            return granted
        } catch {
            await checkAuthorizationStatus()
            return false
        }
    }

    /// Checks the current notification authorization status and updates published properties.
    func checkAuthorizationStatus() async {
        let settings = await notificationCenter.notificationSettings()
        authorizationStatus = settings.authorizationStatus
        isAuthorized = settings.authorizationStatus == .authorized
    }

    // MARK: - Category Configuration

    /// Configures notification categories with interactive actions for locus proximity alerts.
    private func configureCategories() {
        let viewAction = UNNotificationAction(
            identifier: Self.viewLocusActionIdentifier,
            title: String(localized: "View"),
            options: .foreground
        )

        let addNoteAction = UNNotificationAction(
            identifier: Self.addNoteActionIdentifier,
            title: String(localized: "Add Note"),
            options: .foreground
        )

        let archiveAction = UNNotificationAction(
            identifier: Self.archiveActionIdentifier,
            title: String(localized: "Archive"),
            options: .destructive
        )

        let locusCategory = UNNotificationCategory(
            identifier: Self.locusCategoryIdentifier,
            actions: [viewAction, addNoteAction, archiveAction],
            intentIdentifiers: [],
            options: []
        )

        notificationCenter.setNotificationCategories([locusCategory])
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Handle notifications when app is in the foreground — show them as banners.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge]
    }

    /// Handle notification tap and action responses.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo

        switch response.actionIdentifier {
        case Self.viewLocusActionIdentifier,
             UNNotificationDefaultActionIdentifier:
            if let locusId = userInfo["locusId"] as? String {
                NotificationCenter.default.post(
                    name: .notificationTappedViewLocus,
                    object: nil,
                    userInfo: ["locusId": locusId]
                )
            }

        case Self.addNoteActionIdentifier:
            if let locusId = userInfo["locusId"] as? String {
                NotificationCenter.default.post(
                    name: .notificationTappedAddNote,
                    object: nil,
                    userInfo: ["locusId": locusId]
                )
            }

        case Self.archiveActionIdentifier:
            if let locusId = userInfo["locusId"] as? String {
                NotificationCenter.default.post(
                    name: .notificationTappedArchive,
                    object: nil,
                    userInfo: ["locusId": locusId]
                )
            }

        default:
            break
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let notificationTappedViewLocus = Notification.Name("NotificationTappedViewLocus")
    static let notificationTappedAddNote = Notification.Name("NotificationTappedAddNote")
    static let notificationTappedArchive = Notification.Name("NotificationTappedArchive")
}
