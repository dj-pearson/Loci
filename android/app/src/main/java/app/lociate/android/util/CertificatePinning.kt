package app.lociate.android.util

import app.lociate.android.BuildConfig
import okhttp3.CertificatePinner

/**
 * Certificate pinning configuration for Supabase API traffic.
 *
 * Pins are read from BuildConfig (sourced from local.properties / CI env vars
 * via scripts/generate-secrets.sh). Attached to the Ktor OkHttp engine in
 * SupabaseClientProvider so every outbound Supabase request is pinned.
 *
 * Extract production hashes with:
 *
 *   openssl s_client -connect <host>:443 -servername <host> </dev/null 2>/dev/null \
 *     | openssl x509 -pubkey -noout \
 *     | openssl pkey -pubin -outform DER \
 *     | openssl dgst -sha256 -binary \
 *     | base64
 */
object CertificatePinning {

    private const val SUPABASE_DOMAIN_PATTERN = "*.supabase.co"

    /**
     * Builds an OkHttp CertificatePinner using BuildConfig-injected SPKI pins.
     * Returns an empty pinner (no-op) if no pins are configured — this matches
     * the iOS behaviour of disabling pinning when `BuildSecrets.certificatePinHash`
     * is empty.
     */
    fun createCertificatePinner(
        domainPattern: String = SUPABASE_DOMAIN_PATTERN,
        primaryPin: String = BuildConfig.CERT_PIN_HASH,
        backupPin: String = BuildConfig.CERT_BACKUP_PIN_HASH,
    ): CertificatePinner {
        val builder = CertificatePinner.Builder()
        if (primaryPin.isNotEmpty()) {
            builder.add(domainPattern, "sha256/$primaryPin")
        }
        if (backupPin.isNotEmpty()) {
            builder.add(domainPattern, "sha256/$backupPin")
        }
        return builder.build()
    }

    /**
     * True when at least one SPKI pin is configured. Callers can use this to
     * decide whether pinning is active in the current build.
     */
    fun isPinningEnabled(): Boolean =
        BuildConfig.CERT_PIN_HASH.isNotEmpty() || BuildConfig.CERT_BACKUP_PIN_HASH.isNotEmpty()

    /**
     * Validates that a URL targets one of the expected API hosts. Prevents
     * accidental egress to arbitrary domains.
     */
    fun isAllowedDomain(url: String): Boolean {
        val allowedDomains = listOf(
            "supabase.co",
            "supabase.com",
            "googleapis.com",
        )
        return allowedDomains.any { domain -> url.contains(domain, ignoreCase = true) }
    }
}
