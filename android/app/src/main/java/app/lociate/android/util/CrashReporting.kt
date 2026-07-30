package app.lociate.android.util

import android.content.Context
import app.lociate.android.BuildConfig
import io.sentry.Sentry
import io.sentry.SentryEvent
import io.sentry.SentryLevel
import io.sentry.android.core.SentryAndroid
import timber.log.Timber

/**
 * Crash and error reporting (US-199).
 *
 * Nothing reported crashes before this, on either platform — a launch-day crash
 * loop would have been invisible until App Store or Play reviews arrived.
 *
 * An empty DSN disables reporting entirely, so a self-hosted or contributor build
 * needs no Sentry account.
 */
object CrashReporting {

    /**
     * Field names and value patterns that must never leave the device.
     *
     * A voice note's transcription and the coordinate it is pinned to are the two
     * most sensitive things this app holds; a stack frame or breadcrumb carrying
     * either would turn crash reporting into a data leak.
     */
    private val SENSITIVE_KEYS = setOf(
        "apns_token",
        "audio_file_path",
        "audiofileurl",
        "email",
        "fcm_token",
        "invite_code",
        "latitude",
        "location_name",
        "longitude",
        "password",
        "transcription",
    )

    private val COORDINATE_PATTERN = Regex("""-?\d{1,3}\.\d{4,}""")
    private val EMAIL_PATTERN = Regex("""[\w.+-]+@[\w-]+\.[\w.]+""")

    fun initialize(context: Context) {
        val dsn = BuildConfig.SENTRY_DSN
        if (dsn.isBlank()) {
            Timber.i("SENTRY_DSN not set — crash reporting disabled")
            return
        }

        SentryAndroid.init(context) { options ->
            options.dsn = dsn
            // Grouping per release, so a regression is attributable to a build.
            options.release = "${BuildConfig.APPLICATION_ID}@${BuildConfig.VERSION_NAME}+${BuildConfig.VERSION_CODE}"
            options.environment = if (BuildConfig.DEBUG) "debug" else "production"

            // Sentry's own defaults would attach the device's IP and PII.
            options.isSendDefaultPii = false
            options.isAttachScreenshot = false
            options.isAttachViewHierarchy = false

            // Performance traces are not worth the payload for a launch; errors are.
            options.tracesSampleRate = 0.0

            options.beforeSend = io.sentry.SentryOptions.BeforeSendCallback { event, _ ->
                scrub(event)
            }

            options.beforeBreadcrumb = io.sentry.SentryOptions.BeforeBreadcrumbCallback { crumb, _ ->
                crumb.message = crumb.message?.let(::scrubText)
                crumb.data.keys.toList().forEach { key ->
                    if (key.lowercase() in SENSITIVE_KEYS) {
                        crumb.data[key] = REDACTED
                    } else {
                        (crumb.data[key] as? String)?.let { crumb.data[key] = scrubText(it) }
                    }
                }
                crumb
            }
        }

        Timber.i("Crash reporting initialized")
    }

    /** Attaches the hashed user id, mirroring the analytics identity rule. */
    fun setUser(hashedUserId: String?) {
        if (BuildConfig.SENTRY_DSN.isBlank()) return
        Sentry.setUser(
            hashedUserId?.let {
                io.sentry.protocol.User().apply { id = it }
            }
        )
    }

    /** Reports a handled error that the user should not have to notice. */
    fun captureException(throwable: Throwable, context: Map<String, String> = emptyMap()) {
        if (BuildConfig.SENTRY_DSN.isBlank()) return
        Sentry.withScope { scope ->
            context.forEach { (key, value) ->
                scope.setTag(
                    key,
                    if (key.lowercase() in SENSITIVE_KEYS) REDACTED else scrubText(value)
                )
            }
            Sentry.captureException(throwable)
        }
    }

    private fun scrub(event: SentryEvent): SentryEvent {
        event.message?.let { it.formatted = it.formatted?.let(::scrubText) }

        // Exception *values* are the interpolated message; the type and stack frames
        // carry no user data.
        event.exceptions?.forEach { exception ->
            exception.value = exception.value?.let(::scrubText)
        }

        event.extras?.keys?.toList()?.forEach { key ->
            if (key.lowercase() in SENSITIVE_KEYS) {
                event.setExtra(key, REDACTED)
            }
        }

        event.tags?.keys?.toList()?.forEach { key ->
            if (key.lowercase() in SENSITIVE_KEYS) event.setTag(key, REDACTED)
        }

        // Never let Sentry's default level escalate a debug log into an alert.
        if (event.level == null) event.level = SentryLevel.ERROR
        return event
    }

    /**
     * Redacts coordinates and email addresses from free text.
     *
     * Exception messages routinely interpolate a file path or a coordinate, so
     * key-based redaction alone is not enough for message bodies.
     */
    internal fun scrubText(text: String): String =
        text
            .replace(EMAIL_PATTERN, REDACTED)
            .replace(COORDINATE_PATTERN, REDACTED)

    internal const val REDACTED = "[redacted]"
}
