import Foundation
import SwiftData
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

    /// Whether quiet hours are currently active (exposed for UI status indicator).
    var isQuietHoursActive: Bool {
        isInQuietHours()
    }

    // MARK: - Queued Notifications

    /// Notifications suppressed during quiet hours, keyed by locus ID.
    private var queuedNotifications: [UUID: Locus] = []
    private var quietHoursEndTimer: Timer?

    /// Delivers any queued notifications that were suppressed during quiet hours.
    /// Called when quiet hours end or when the app returns to foreground outside quiet hours.
    func deliverQueuedNotifications() {
        guard !isInQuietHours() else { return }
        for (_, locus) in queuedNotifications {
            scheduleGeofenceNotificationImmediate(for: locus)
        }
        queuedNotifications.removeAll()
    }

    // MARK: - Geofence Notifications

    /// Returns `true` if the current time falls within the user's configured quiet hours.
    func isInQuietHours() -> Bool {
        guard UserDefaults.standard.bool(forKey: "loci_notifications_enabled") else {
            return true // Notifications disabled entirely
        }

        guard let startDate = UserDefaults.standard.object(forKey: "loci_quiet_hours_start") as? Date,
              let endDate = UserDefaults.standard.object(forKey: "loci_quiet_hours_end") as? Date else {
            return false
        }

        let calendar = Calendar.current
        let now = Date()
        let startComponents = calendar.dateComponents([.hour, .minute], from: startDate)
        let endComponents = calendar.dateComponents([.hour, .minute], from: endDate)
        let nowComponents = calendar.dateComponents([.hour, .minute], from: now)

        guard let startMinutes = startComponents.hour.map({ $0 * 60 + (startComponents.minute ?? 0) }),
              let endMinutes = endComponents.hour.map({ $0 * 60 + (endComponents.minute ?? 0) }),
              let nowMinutes = nowComponents.hour.map({ $0 * 60 + (nowComponents.minute ?? 0) }) else {
            return false
        }

        if startMinutes <= endMinutes {
            return nowMinutes >= startMinutes && nowMinutes < endMinutes
        } else {
            // Crosses midnight (e.g., 22:00 - 07:00)
            return nowMinutes >= startMinutes || nowMinutes < endMinutes
        }
    }

    /// Schedules a local notification for a geofence entry event.
    /// Shows the locus location name, transcription preview, category, and relative time.
    /// Notifications are suppressed during quiet hours.
    func scheduleGeofenceNotification(for locus: Locus) {
        guard !isInQuietHours() else {
            // Queue for delivery when quiet hours end
            queuedNotifications[locus.id] = locus
            return
        }
        scheduleGeofenceNotificationImmediate(for: locus)
    }

    /// Internal: schedules the notification without checking quiet hours.
    private func scheduleGeofenceNotificationImmediate(for locus: Locus) {
        let content = UNMutableNotificationContent()

        // Title: distinguish personal vs shared loci
        if locus.isShared, let creatorName = locus.createdByName {
            content.title = String(localized: "\(creatorName) left a note here:")
        } else {
            content.title = locus.locationName ?? String(localized: "You left a note here")
        }

        // Body: first 100 characters of transcription
        if locus.transcription.count > 100 {
            content.body = String(locus.transcription.prefix(100)) + "…"
        } else {
            content.body = locus.transcription
        }

        // Subtitle for shared loci: include location name
        if locus.isShared, locus.createdByName != nil, let locationName = locus.locationName {
            content.subtitle = "\(locationName) · \(locus.category.displayName)"
        }

        // Subtitle: category name and relative time
        let relativeTime = Self.relativeTimeString(from: locus.createdAt)
        content.subtitle = "\(locus.category.displayName) · \(relativeTime)"

        content.sound = .default
        content.categoryIdentifier = Self.locusCategoryIdentifier
        content.userInfo = ["locusId": locus.id.uuidString]

        let request = UNNotificationRequest(
            identifier: "geofence-\(locus.id.uuidString)",
            content: content,
            trigger: nil // Deliver immediately
        )

        notificationCenter.add(request)
    }

    /// Returns a human-readable relative time string (e.g., "3 weeks ago", "just now").
    private static func relativeTimeString(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
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
