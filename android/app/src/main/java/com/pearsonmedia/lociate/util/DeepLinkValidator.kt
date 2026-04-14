package com.pearsonmedia.loci.util

import android.content.Intent
import android.net.Uri
import timber.log.Timber

/**
 * Validates deep-link URIs to prevent intent injection attacks.
 * Only allows known schemes and hosts.
 */
object DeepLinkValidator {

    private const val SCHEME = "loci"
    private const val HOST_LOCUS = "locus"

    /**
     * Validates and extracts a locus ID from a deep-link intent.
     * Returns null if the intent is not a valid Loci deep-link.
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
        // Only accept loci:// scheme
        if (uri.scheme != SCHEME) {
            Timber.w("Rejected deep-link with unknown scheme: ${uri.scheme}")
            return null
        }

        // Only accept loci://locus/{id}
        if (uri.host != HOST_LOCUS) {
            Timber.w("Rejected deep-link with unknown host: ${uri.host}")
            return null
        }

        val locusId = uri.lastPathSegment
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
