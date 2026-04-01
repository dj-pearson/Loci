import CryptoKit
import Foundation
import os.log

// MARK: - Analytics Event

enum AnalyticsEvent: String {
    case appLaunch = "app_launch"
    case locusCreated = "locus_created"
    case locusViewed = "locus_viewed"
    case locusTriggered = "locus_triggered"
    case recordingStarted = "recording_started"
    case recordingCompleted = "recording_completed"
    case searchPerformed = "search_performed"
    case householdCreated = "household_created"
    case householdJoined = "household_joined"
    case paywallShown = "paywall_shown"
    case subscriptionPurchased = "subscription_purchased"
    case subscriptionCancelled = "subscription_cancelled"
    case geofenceTriggered = "geofence_triggered"
}

// MARK: - Analytics Service

@Observable
final class AnalyticsService {
    static let shared = AnalyticsService()

    private static let appID = "LOCI_TELEMETRYDECK_APP_ID"
    private static let optOutKey = "loci_analytics_opt_out"
    private let logger = Logger(subsystem: "com.pearsonmedia.loci", category: "Analytics")

    var isOptedOut: Bool {
        get { UserDefaults.standard.bool(forKey: Self.optOutKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.optOutKey) }
    }

    private var isDebug: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    private init() {}

    // MARK: - Configuration

    func configure() {
        guard !isOptedOut else {
            logger.info("Analytics opted out, skipping configuration")
            return
        }

        if isDebug {
            logger.info("TelemetryDeck configured in debug mode (console-only)")
        } else {
            // TelemetryDeck.initialize(config: .init(appID: Self.appID))
            logger.info("TelemetryDeck configured for production")
        }
    }

    // MARK: - Event Tracking

    func track(_ event: AnalyticsEvent, parameters: [String: String] = [:]) {
        guard !isOptedOut else { return }

        if isDebug {
            let params = parameters.isEmpty ? "" : " \(parameters)"
            logger.debug("📊 [Analytics] \(event.rawValue)\(params)")
            return
        }

        // TelemetryDeck.signal(event.rawValue, parameters: parameters)
    }

    // MARK: - Convenience Methods

    func trackLocusCreated(category: String) {
        track(.locusCreated, parameters: ["category": category])
    }

    func trackLocusTriggered() {
        track(.locusTriggered)
    }

    func trackRecordingStarted() {
        track(.recordingStarted)
    }

    func trackRecordingCompleted() {
        track(.recordingCompleted)
    }

    func trackSearchPerformed() {
        track(.searchPerformed)
    }

    func trackHouseholdCreated() {
        track(.householdCreated)
    }

    func trackHouseholdJoined() {
        track(.householdJoined)
    }

    func trackPaywallShown() {
        track(.paywallShown)
    }

    func trackSubscriptionPurchased() {
        track(.subscriptionPurchased)
    }

    func trackSubscriptionCancelled() {
        track(.subscriptionCancelled)
    }

    func trackAppLaunch() {
        track(.appLaunch)
    }

    func trackLocusViewed() {
        track(.locusViewed)
    }

    func trackGeofenceTriggered() {
        track(.geofenceTriggered)
    }

    // MARK: - User Identity (Hashed)

    /// Sets the TelemetryDeck user identifier as a SHA-256 hash of the user ID.
    /// No raw PII is sent to analytics.
    func setUser(id: String) {
        let hashed = SHA256.hash(data: Data(id.utf8))
            .compactMap { String(format: "%02x", $0) }
            .joined()

        if isDebug {
            logger.debug("📊 [Analytics] User set: \(hashed.prefix(12))...")
        }
        // TelemetryDeck.updateDefaultUser(to: hashed)
    }

    func clearUser() {
        if isDebug {
            logger.debug("📊 [Analytics] User cleared")
        }
        // TelemetryDeck.updateDefaultUser(to: nil)
    }
}
