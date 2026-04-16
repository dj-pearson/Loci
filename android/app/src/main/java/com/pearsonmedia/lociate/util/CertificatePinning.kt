package com.pearsonmedia.lociate.util

import android.content.Context
import java.io.InputStream
import java.security.KeyStore
import java.security.cert.CertificateFactory
import javax.net.ssl.SSLContext
import javax.net.ssl.TrustManagerFactory
import javax.net.ssl.X509TrustManager
import okhttp3.CertificatePinner

/**
 * Certificate pinning configuration for Supabase API domain.
 * Pins the SHA-256 hash of the server's public key to prevent MITM attacks.
 *
 * In production, replace the placeholder pins with actual certificate hashes
 * obtained via: openssl s_client -connect your-supabase-url:443 | openssl x509 -pubkey | openssl pkey -pubin -outform der | openssl dgst -sha256 -binary | openssl enc -base64
 */
object CertificatePinning {

    // Replace with your actual Supabase domain and certificate hashes
    private const val SUPABASE_DOMAIN = "*.supabase.co"

    /**
     * Creates an OkHttp CertificatePinner for Supabase connections.
     * Add the actual SHA-256 pins from your Supabase server certificate chain.
     */
    fun createCertificatePinner(supabaseDomain: String = SUPABASE_DOMAIN): CertificatePinner {
        return CertificatePinner.Builder()
            // Pin the leaf certificate and one intermediate CA for rotation safety
            // Replace these with actual pins from your Supabase deployment
            .add(supabaseDomain, "sha256/AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=") // leaf
            .add(supabaseDomain, "sha256/BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=") // intermediate
            .build()
    }

    /**
     * Validates that a domain is an expected API endpoint.
     * Prevents connections to unexpected domains.
     */
    fun isAllowedDomain(url: String): Boolean {
        val allowedDomains = listOf(
            "supabase.co",
            "supabase.com",
            "googleapis.com" // For Google Maps and auth
        )
        return allowedDomains.any { domain ->
            url.contains(domain, ignoreCase = true)
        }
    }
}
