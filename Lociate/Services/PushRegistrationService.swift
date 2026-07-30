import Foundation
import os.log
import Supabase
import UIKit

/// Registers the device with APNs and keeps `users.apns_token` in sync (US-195).
///
/// Everything downstream of a device token already existed — the entitlement
/// declares `aps-environment`, Info.plist declares the `remote-notification`
/// background mode, `users.apns_token` is a column, and the digest edge function
/// reads it — but nothing ever called `registerForRemoteNotifications()`, so the
/// column was always null and every server-side push was skipped.
@Observable
final class PushRegistrationService {
    static let shared = PushRegistrationService()

    private let logger = Logger(subsystem: "app.lociate.ios", category: "PushRegistration")
    private let defaults: UserDefaults
    private let supabase: SupabaseClient

    /// Last token we successfully wrote, so a repeat launch does not re-upsert.
    private static let syncedTokenKey = "push_synced_apns_token"
    /// Token obtained but not yet persisted server-side (offline, or signed out).
    private static let pendingTokenKey = "push_pending_apns_token"

    private(set) var currentToken: String?
    private(set) var lastError: String?

    init(
        defaults: UserDefaults = .standard,
        supabase: SupabaseClient = SupabaseClientProvider.shared
    ) {
        self.defaults = defaults
        self.supabase = supabase
        currentToken = defaults.string(forKey: Self.syncedTokenKey)
            ?? defaults.string(forKey: Self.pendingTokenKey)
    }

    // MARK: - Registration

    /// Asks iOS for a device token.
    ///
    /// Must only be called once notification authorization has been granted:
    /// registering first produces a token the user has not consented to receive
    /// alerts on, and iOS may not deliver one at all.
    @MainActor
    func registerIfAuthorized(isAuthorized: Bool) {
        guard isAuthorized else {
            logger.debug("Notification permission not granted — skipping APNs registration")
            return
        }
        UIApplication.shared.registerForRemoteNotifications()
    }

    // MARK: - Token lifecycle

    /// Called from the app delegate when APNs hands back a device token.
    func handleRegistration(deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        currentToken = token
        lastError = nil

        guard token != defaults.string(forKey: Self.syncedTokenKey) else {
            logger.debug("APNs token unchanged — nothing to upsert")
            return
        }

        defaults.set(token, forKey: Self.pendingTokenKey)
        Task { await syncPendingToken() }
    }

    /// Called from the app delegate when registration fails.
    ///
    /// A failure here must never be fatal: no push is a degraded experience, but
    /// geofence notifications are local and keep working regardless.
    func handleRegistrationFailure(_ error: Error) {
        lastError = error.localizedDescription
        logger.error("APNs registration failed: \(error.localizedDescription, privacy: .public)")
    }

    /// Retries a queued upsert. Safe to call repeatedly — it no-ops when there is
    /// nothing pending, no session, or no connectivity.
    func syncPendingToken() async {
        guard let token = defaults.string(forKey: Self.pendingTokenKey) else { return }

        guard let userId = await currentUserId() else {
            // Signed out: keep the token queued for after the next sign-in.
            logger.debug("No session — leaving APNs token queued")
            return
        }

        do {
            try await supabase
                .from("users")
                .update(["apns_token": token])
                .eq("auth_id", value: userId)
                .execute()

            defaults.set(token, forKey: Self.syncedTokenKey)
            defaults.removeObject(forKey: Self.pendingTokenKey)
            logger.info("APNs token registered for the current user")
        } catch {
            // Stays pending; retried on the next connectivity change, sign-in, or
            // foreground.
            logger.error("Failed to upsert APNs token: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Called after a successful sign-in, so a token obtained before the user had
    /// a session still reaches the server.
    func handleSignIn() async {
        // Force a re-upsert: this token now belongs to a different account.
        if let token = currentToken {
            defaults.set(token, forKey: Self.pendingTokenKey)
            defaults.removeObject(forKey: Self.syncedTokenKey)
        }
        await syncPendingToken()
    }

    /// Clears the stored token server-side and locally.
    ///
    /// Without this, a signed-out device keeps receiving another account's
    /// digests, and a shared device leaks notifications across users.
    func handleSignOut() async {
        defer {
            defaults.removeObject(forKey: Self.syncedTokenKey)
            defaults.removeObject(forKey: Self.pendingTokenKey)
            currentToken = nil
        }

        guard let userId = await currentUserId() else { return }

        do {
            try await supabase
                .from("users")
                .update(["apns_token": String?.none])
                .eq("auth_id", value: userId)
                .execute()
            logger.info("APNs token cleared for the signed-out user")
        } catch {
            logger.error("Failed to clear APNs token: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Drops local token state after account deletion. The row is already gone,
    /// so there is nothing to clear server-side.
    func handleAccountDeleted() {
        defaults.removeObject(forKey: Self.syncedTokenKey)
        defaults.removeObject(forKey: Self.pendingTokenKey)
        currentToken = nil
    }

    // MARK: - Helpers

    private func currentUserId() async -> String? {
        do {
            return try await supabase.auth.session.user.id.uuidString
        } catch {
            return nil
        }
    }
}
