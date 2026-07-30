import Foundation
import os.log
import Sentry

/// Crash and error reporting (US-199).
///
/// Nothing reported crashes before this on any surface — a launch-day crash loop
/// would have been invisible until App Store reviews arrived.
///
/// An empty DSN disables reporting entirely, so a contributor build needs no
/// Sentry account.
enum CrashReportingService {

    private static let logger = Logger(subsystem: "app.lociate.ios", category: "CrashReporting")

    private(set) static var isEnabled = false

    /// Keys that must never leave the device.
    ///
    /// A transcription and the coordinate it is pinned to are the two most
    /// sensitive things this app holds; a breadcrumb carrying either would turn
    /// crash reporting into a data leak.
    private static let sensitiveKeys: Set<String> = [
        "apnstoken",
        "apns_token",
        "audiofileurl",
        "audio_file_path",
        "email",
        "invitecode",
        "invite_code",
        "latitude",
        "locationname",
        "location_name",
        "longitude",
        "password",
        "transcription",
    ]

    private static let redacted = "[redacted]"

    /// Matches a decimal coordinate at map precision. Exception messages routinely
    /// interpolate one, so key-based redaction alone is not enough for free text.
    private static let coordinatePattern = try? NSRegularExpression(
        pattern: #"-?\d{1,3}\.\d{4,}"#
    )
    private static let emailPattern = try? NSRegularExpression(
        pattern: #"[\w.+-]+@[\w-]+\.[\w.]+"#
    )

    // MARK: - Lifecycle

    static func configure() {
        let dsn = BuildSecrets.sentryDSN
        guard !dsn.isEmpty else {
            logger.info("Sentry DSN not configured, crash reporting disabled")
            return
        }

        SentrySDK.start { options in
            options.dsn = dsn

            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
            let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
            options.releaseName = "app.lociate.ios@\(version)+\(build)"

            #if DEBUG
            options.environment = "debug"
            // Debug crashes are the developer's to see in the console; shipping them
            // would drown the production signal.
            options.enabled = false
            #else
            options.environment = "production"
            #endif

            // Sentry's defaults would attach the device IP and screenshots.
            options.sendDefaultPii = false
            options.attachScreenshot = false
            options.attachViewHierarchy = false
            options.tracesSampleRate = 0

            options.beforeSend = { event in
                scrub(event)
            }

            options.beforeBreadcrumb = { crumb in
                crumb.message = crumb.message.map(scrubText)
                if let data = crumb.data {
                    crumb.data = scrub(dictionary: data)
                }
                return crumb
            }
        }

        isEnabled = true
        logger.info("Crash reporting initialized")
    }

    /// Attaches the SHA-256-hashed user id, mirroring the analytics identity rule.
    static func setUser(hashedId: String?) {
        guard isEnabled else { return }
        guard let hashedId else {
            SentrySDK.setUser(nil)
            return
        }
        let user = User()
        user.userId = hashedId
        SentrySDK.setUser(user)
    }

    /// Reports a handled error the user should not have to notice.
    static func capture(_ error: Error, context: [String: String] = [:]) {
        guard isEnabled else { return }
        SentrySDK.capture(error: error) { scope in
            for (key, value) in context {
                scope.setTag(
                    value: sensitiveKeys.contains(key.lowercased()) ? redacted : scrubText(value),
                    key: key
                )
            }
        }
    }

    // MARK: - Scrubbing

    private static func scrub(_ event: Event) -> Event? {
        // SentryMessage.formatted is readonly, and `.map` on a String maps over its
        // Characters — the previous one-liner was wrong three different ways. Replace
        // the whole message instead.
        if let formatted = event.message?.formatted {
            event.message = SentryMessage(formatted: scrubText(formatted))
        }

        // Exception *values* are the interpolated message; the type and stack frames
        // carry no user data.
        event.exceptions = event.exceptions?.map { exception in
            exception.value = scrubText(exception.value)
            return exception
        }

        if let extra = event.extra {
            event.extra = scrub(dictionary: extra)
        }
        if let tags = event.tags {
            event.tags = tags.mapValues { scrubText($0) }
        }
        return event
    }

    private static func scrub(dictionary: [String: Any], depth: Int = 0) -> [String: Any] {
        guard depth <= 4 else { return dictionary }

        return dictionary.reduce(into: [String: Any]()) { result, entry in
            let (key, value) = entry
            if sensitiveKeys.contains(key.lowercased()) {
                result[key] = redacted
            } else if let nested = value as? [String: Any] {
                result[key] = scrub(dictionary: nested, depth: depth + 1)
            } else if let text = value as? String {
                result[key] = scrubText(text)
            } else {
                result[key] = value
            }
        }
    }

    /// Redacts coordinates and email addresses from free text.
    static func scrubText(_ text: String) -> String {
        var output = text
        for pattern in [emailPattern, coordinatePattern].compactMap({ $0 }) {
            output = pattern.stringByReplacingMatches(
                in: output,
                range: NSRange(output.startIndex..., in: output),
                withTemplate: redacted
            )
        }
        return output
    }
}
