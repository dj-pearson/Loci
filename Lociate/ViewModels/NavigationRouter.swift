import Foundation
import SwiftUI

@Observable
final class NavigationRouter {
    // MARK: - Deep-Link State

    /// The locus ID to navigate to when set. Views observe this to trigger navigation.
    var selectedLocusId: UUID?

    /// Pending locus ID from a notification received before the UI was ready.
    /// Consumed once the main view appears.
    private var pendingLocusId: UUID?

    // MARK: - Notification Observers

    private var notificationObservers: [Any] = []

    // MARK: - Initialization

    init() {
        observeNotifications()
    }

    deinit {
        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Deep-Link Handling

    /// Call from the main view's onAppear to consume any pending deep-link
    /// that arrived before the UI was ready (e.g., cold launch from notification).
    func consumePendingDeepLink() {
        if let pending = pendingLocusId {
            selectedLocusId = pending
            pendingLocusId = nil
        }
    }

    /// Navigates to a locus detail view by its UUID string.
    /// If the string is not a valid UUID, the request is ignored.
    func navigateToLocus(idString: String) {
        guard let uuid = UUID(uuidString: idString) else { return }
        selectedLocusId = uuid
    }

    /// Clears the current deep-link selection.
    func clearSelection() {
        selectedLocusId = nil
    }

    // MARK: - Notification Observers

    private func observeNotifications() {
        // View Locus (notification tap or VIEW_LOCUS action)
        let viewObserver = NotificationCenter.default.addObserver(
            forName: .notificationTappedViewLocus,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let locusId = notification.userInfo?["locusId"] as? String else { return }
            self.handleDeepLink(locusIdString: locusId)
        }

        // Add Note action — navigate to locus first, then the view can handle add-note mode
        let addNoteObserver = NotificationCenter.default.addObserver(
            forName: .notificationTappedAddNote,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let locusId = notification.userInfo?["locusId"] as? String else { return }
            self.handleDeepLink(locusIdString: locusId)
        }

        notificationObservers = [viewObserver, addNoteObserver]
    }

    /// Routes a deep-link. If the app UI is ready (selectedLocusId can be observed),
    /// sets it immediately. Otherwise, stores as pending for consumption on appear.
    private func handleDeepLink(locusIdString: String) {
        guard let uuid = UUID(uuidString: locusIdString) else { return }

        // Set both: selectedLocusId for immediate navigation if UI is ready,
        // pendingLocusId as fallback for cold launch.
        selectedLocusId = uuid
        pendingLocusId = uuid
    }

    // MARK: - URL Scheme Handling

    /// Set to `true` when a paywall deep-link is received (e.g., from widget locked state).
    var showPaywall = false

    /// Processes a `loci://` URL scheme for deep-linking from widgets and notifications.
    /// Supported paths:
    /// - `loci://detail/{locusId}` — navigates to locus detail
    /// - `loci://paywall` — opens the paywall
    func handleURL(_ url: URL) {
        guard url.scheme == "loci" else { return }

        switch url.host {
        case "detail":
            let idString = url.lastPathComponent
            handleDeepLink(locusIdString: idString)
        case "paywall":
            showPaywall = true
        default:
            break
        }
    }
}
