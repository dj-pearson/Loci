package app.lociate.android.util

import android.content.Intent
import android.net.Uri
import timber.log.Timber

/**
 * Validates deep-link URIs to prevent intent injection attacks.
 * Only allows known schemes and hosts.
 */
object DeepLinkValidator {

    /**
     * US-203: the manifest declared `lociate://locus` while this validator only
     * accepted `loci://locus`, so every deep link the app could actually receive
     * was rejected. Both custom schemes are now accepted — `lociate` canonical,
     * `loci` for parity with links already emitted by the iOS widget — alongside
     * https App Links.
     */
    private val CUSTOM_SCHEMES = setOf("lociate", "loci")
    private const val HTTPS_SCHEME = "https"
    private const val HOST_LOCUS = "locus"

    /** Hosts permitted for https App Links; must match web/public/.well-known/assetlinks.json. */
    private val APP_LINK_HOSTS = setOf("lociate.app", "www.lociate.app")

    /** Path prefixes permitted for https App Links; must match the AASA paths. */
    private val APP_LINK_PATH_PREFIXES = setOf("locus", "open")

    /**
     * Validates and extracts a locus ID from a deep-link intent.
     * Returns null if the intent is not a valid Lociate deep-link.
     */
    fun extractLocusId(intent: Intent?): String? {
        if (intent == null) return null

        // Check for explicit extra first (from notification PendingIntent)
        intent.getStringExtra("locus_id")?.let { id ->
            if (isValidUuid(id)) return id
        }

        // Check for deep-link URI
        val uri = intent.data ?: return null
        return extractLocusIdFromUri(uri)
    }

    /**
     * Validates a deep-link URI and extracts the locus ID.
     */
    fun extractLocusIdFromUri(uri: Uri): String? {
        val locusId = when (uri.scheme) {
            in CUSTOM_SCHEMES -> {
                if (uri.host != HOST_LOCUS) {
                    Timber.w("Rejected deep-link with unknown host: ${uri.host}")
                    return null
                }
                uri.lastPathSegment
            }

            HTTPS_SCHEME -> {
                if (uri.host !in APP_LINK_HOSTS) {
                    Timber.w("Rejected App Link with unknown host: ${uri.host}")
                    return null
                }
                val segments = uri.pathSegments
                if (segments.size < 2 || segments[0] !in APP_LINK_PATH_PREFIXES) {
                    Timber.w("Rejected App Link with unexpected path: ${uri.path}")
                    return null
                }
                segments[1]
            }

            else -> {
                Timber.w("Rejected deep-link with unknown scheme: ${uri.scheme}")
                return null
            }
        }

        // The UUID check is the injection guard: it runs on every accepted route.
        if (locusId == null || !isValidUuid(locusId)) {
            Timber.w("Rejected deep-link with invalid locus ID: $locusId")
            return null
        }

        return locusId
    }

    /**
     * Validates that a string is a valid UUID format.
     * Prevents path traversal and injection via malformed IDs.
     */
    private fun isValidUuid(value: String): Boolean {
        return value.matches(
            Regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$")
        )
    }
}
