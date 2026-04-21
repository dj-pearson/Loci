package app.lociate.android.util

import app.lociate.android.BuildConfig
import okhttp3.Interceptor
import okhttp3.Response
import okio.Buffer
import java.security.MessageDigest
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

/**
 * OkHttp interceptor that adds HMAC-SHA256 request signatures to outbound
 * requests, matching the iOS `RequestSigningService` and the edge-function
 * `requestSigningMiddleware`.
 *
 * Headers added when `BuildConfig.REQUEST_SIGNING_KEY` is non-empty:
 * - `X-Client-Version`: "<versionName>(<versionCode>)"
 * - `X-Request-Timestamp`: ISO 8601 timestamp (UTC)
 * - `X-Request-Signature`: HMAC-SHA256(METHOD\nPATH\nTIMESTAMP\nBODY_SHA256)
 *
 * When the key is empty (local dev), the interceptor is a no-op and the
 * server-side middleware will also skip validation.
 *
 * NOTE: This interceptor is currently **not attached** to the supabase-kt
 * HttpClient. To enable, configure Ktor with an OkHttp engine in
 * SupabaseClientProvider and add this interceptor to the OkHttpClient builder.
 */
class RequestSigningInterceptor(
    private val signingKey: String = BuildConfig.REQUEST_SIGNING_KEY,
    private val clientVersion: String =
        "${BuildConfig.VERSION_NAME}(${BuildConfig.VERSION_CODE})",
) : Interceptor {

    override fun intercept(chain: Interceptor.Chain): Response {
        val original = chain.request()
        if (signingKey.isEmpty()) return chain.proceed(original)

        val timestamp = iso8601Formatter().format(Date())
        val method = original.method
        val path = original.url.encodedPath
        val bodyBytes = original.body?.let { body ->
            val buffer = Buffer()
            body.writeTo(buffer)
            buffer.readByteArray()
        } ?: ByteArray(0)
        val bodyHash = sha256Hex(bodyBytes)
        val payload = "$method\n$path\n$timestamp\n$bodyHash"
        val signature = hmacSha256Hex(payload, signingKey)

        val signed = original.newBuilder()
            .header("X-Client-Version", clientVersion)
            .header("X-Request-Timestamp", timestamp)
            .header("X-Request-Signature", signature)
            .build()
        return chain.proceed(signed)
    }

    companion object {
        /** True when a signing key is configured in this build. */
        fun isEnabled(): Boolean = BuildConfig.REQUEST_SIGNING_KEY.isNotEmpty()

        internal fun iso8601Formatter(): SimpleDateFormat =
            SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US).apply {
                timeZone = TimeZone.getTimeZone("UTC")
            }

        internal fun sha256Hex(data: ByteArray): String {
            val digest = MessageDigest.getInstance("SHA-256").digest(data)
            return digest.toHexString()
        }

        internal fun hmacSha256Hex(message: String, key: String): String {
            val mac = Mac.getInstance("HmacSHA256")
            mac.init(SecretKeySpec(key.toByteArray(Charsets.UTF_8), "HmacSHA256"))
            return mac.doFinal(message.toByteArray(Charsets.UTF_8)).toHexString()
        }

        private fun ByteArray.toHexString(): String =
            joinToString(separator = "") { byte -> "%02x".format(byte) }
    }
}
