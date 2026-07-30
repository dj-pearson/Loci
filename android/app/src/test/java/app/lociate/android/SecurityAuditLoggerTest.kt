package app.lociate.android

import app.lociate.android.data.local.dao.AuditLogDao
import app.lociate.android.data.local.entity.AuditLogEntity
import app.lociate.android.service.DeviceInfoProvider
import app.lociate.android.service.SecurityAuditEvent
import app.lociate.android.service.SecurityAuditLogger
import com.google.common.truth.Truth.assertThat
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.test.runTest
import org.junit.Test

/**
 * US-216: iOS has had a security audit trail since US-149; Android had nothing, so
 * a user who suspected their account had been accessed could not check on that
 * platform.
 */
class SecurityAuditLoggerTest {

    private class FakeDao(private val failOnInsert: Boolean = false) : AuditLogDao {
        val inserted = mutableListOf<AuditLogEntity>()
        var trimmedTo: Int? = null
        var cleared = false

        override fun observeRecent(limit: Int): Flow<List<AuditLogEntity>> = flowOf(inserted)
        override suspend fun count(): Int = inserted.size
        override suspend fun insert(entry: AuditLogEntity) {
            if (failOnInsert) throw IllegalStateException("disk full")
            inserted += entry
        }
        override suspend fun trimTo(keep: Int) { trimmedTo = keep }
        override suspend fun clear() { cleared = true }
    }

    private object FakeDeviceInfo : DeviceInfoProvider {
        override fun describe() = "Pixel 8 (Android 15)"
        override fun appVersion() = "1.0.0 (1)"
    }

    private fun logger(dao: AuditLogDao) = SecurityAuditLogger(dao, FakeDeviceInfo)

    @Test
    fun `records the event type and device context`() = runTest {
        val dao = FakeDao()

        logger(dao).log(SecurityAuditEvent.SIGN_IN_SUCCESS, "user@example.com")

        assertThat(dao.inserted).hasSize(1)
        val entry = dao.inserted.single()
        assertThat(entry.eventType).isEqualTo("sign_in_success")
        assertThat(entry.deviceInfo).isEqualTo("Pixel 8 (Android 15)")
        assertThat(entry.appVersion).isEqualTo("1.0.0 (1)")
        assertThat(entry.timestamp).isGreaterThan(0L)
    }

    @Test
    fun `never stores a raw email address`() {
        // This table is unencrypted at the Room layer, so a plaintext address would
        // make the safeguard a liability.
        val hashed = logger(FakeDao()).hashEmail("user@example.com")

        assertThat(hashed).doesNotContain("user@example.com")
        assertThat(hashed).doesNotContain("@")
        assertThat(hashed).hasLength(64)
        assertThat(hashed).matches("[0-9a-f]{64}")
    }

    @Test
    fun `hashing normalizes case and surrounding whitespace`() {
        val logger = logger(FakeDao())

        assertThat(logger.hashEmail("  User@Example.COM  "))
            .isEqualTo(logger.hashEmail("user@example.com"))
    }

    @Test
    fun `different addresses hash differently`() {
        val logger = logger(FakeDao())

        assertThat(logger.hashEmail("a@example.com"))
            .isNotEqualTo(logger.hashEmail("b@example.com"))
    }

    @Test
    fun `an event with no email is recorded as anonymous`() = runTest {
        val dao = FakeDao()

        logger(dao).log(SecurityAuditEvent.SIGN_OUT)

        assertThat(dao.inserted.single().emailHash).isEqualTo(SecurityAuditLogger.ANONYMOUS)
    }

    @Test
    fun `trims after every write so the cap is enforced continuously`() = runTest {
        val dao = FakeDao()

        logger(dao).log(SecurityAuditEvent.SIGN_IN_SUCCESS)

        // Not left to a periodic job that might never run.
        assertThat(dao.trimmedTo).isEqualTo(1000)
    }

    @Test
    fun `a failed write never breaks the flow being observed`() = runTest {
        // Audit logging must not be able to block a sign-in.
        val dao = FakeDao(failOnInsert = true)

        logger(dao).log(SecurityAuditEvent.SIGN_IN_SUCCESS, "user@example.com")

        assertThat(dao.inserted).isEmpty()
    }

    @Test
    fun `event raw values match the iOS SecurityAuditEvent cases`() {
        // Same strings on both platforms, so a shared analysis of the two logs lines
        // up rather than needing a translation table.
        assertThat(SecurityAuditEvent.entries.map { it.rawValue }).containsExactly(
            "sign_in_success",
            "sign_in_failure",
            "sign_up",
            "sign_out",
            "password_reset_request",
            "session_expired",
            "account_deleted",
            "biometric_unlock",
            "biometric_failure",
        )
    }
}
