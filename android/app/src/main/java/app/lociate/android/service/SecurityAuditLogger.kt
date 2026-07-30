package app.lociate.android.service

import app.lociate.android.data.local.dao.AuditLogDao
import app.lociate.android.data.local.entity.AuditLogEntity
import timber.log.Timber
import java.security.MessageDigest
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton

/** Mirrors the iOS `SecurityAuditEvent` cases exactly. */
enum class SecurityAuditEvent(val rawValue: String) {
    SIGN_IN_SUCCESS("sign_in_success"),
    SIGN_IN_FAILURE("sign_in_failure"),
    SIGN_UP("sign_up"),
    SIGN_OUT("sign_out"),
    PASSWORD_RESET_REQUEST("password_reset_request"),
    SESSION_EXPIRED("session_expired"),
    ACCOUNT_DELETED("account_deleted"),
    BIOMETRIC_UNLOCK("biometric_unlock"),
    BIOMETRIC_FAILURE("biometric_failure"),
}

/**
 * Records security-relevant events locally (US-216).
 *
 * iOS has had this since US-149; Android had nothing, so a user who suspected
 * their account had been accessed had no way to check on that platform.
 *
 * Emails are hashed, never stored raw: this table lives unencrypted at the Room
 * layer, so a plaintext address would make the safeguard a liability.
 */
@Singleton
class SecurityAuditLogger @Inject constructor(
    private val auditLogDao: AuditLogDao,
    private val deviceInfoProvider: DeviceInfoProvider,
) {
    /** Matches the iOS cap so both platforms retain a comparable window. */
    private val maxEntries = 1000

    suspend fun log(event: SecurityAuditEvent, email: String? = null) {
        try {
            auditLogDao.insert(
                AuditLogEntity(
                    id = UUID.randomUUID().toString(),
                    eventType = event.rawValue,
                    emailHash = email?.let(::hashEmail) ?: ANONYMOUS,
                    deviceInfo = deviceInfoProvider.describe(),
                    appVersion = deviceInfoProvider.appVersion(),
                    timestamp = System.currentTimeMillis(),
                )
            )
            // Trim after insert so the cap is enforced continuously rather than by a
            // periodic job that might never run.
            auditLogDao.trimTo(maxEntries)
        } catch (e: Exception) {
            // Audit logging must never break the flow it is observing — a failed
            // write here cannot be allowed to block a sign-in.
            Timber.e(e, "Failed to write audit log entry for ${event.rawValue}")
        }
    }

    fun observeRecent(limit: Int = 200) = auditLogDao.observeRecent(limit)

    suspend fun clear() = auditLogDao.clear()

    /**
     * Lowercased and trimmed before hashing so the same address always produces the
     * same hash regardless of how the user typed it.
     */
    internal fun hashEmail(email: String): String {
        val normalized = email.trim().lowercase()
        val digest = MessageDigest.getInstance("SHA-256").digest(normalized.toByteArray())
        return digest.joinToString("") { "%02x".format(it) }
    }

    companion object {
        const val ANONYMOUS = "anonymous"
    }
}

/** Isolated so the logger is testable without an Android runtime. */
interface DeviceInfoProvider {
    fun describe(): String
    fun appVersion(): String
}
