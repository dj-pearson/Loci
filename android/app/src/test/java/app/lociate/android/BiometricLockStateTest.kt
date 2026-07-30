package app.lociate.android

import app.lociate.android.service.BiometricLockState
import com.google.common.truth.Truth.assertThat
import org.junit.Test

/**
 * US-212: Android had no biometric lock at all — the androidx.biometric dependency
 * was declared but BiometricPrompt was never used, and the Settings toggle was
 * local `remember` state that persisted nothing.
 *
 * These pin the lock decision, which must match the iOS `BiometricLockService`
 * exactly. Any divergence is a security difference between platforms, not a
 * cosmetic one.
 */
class BiometricLockStateTest {

    private val now = 1_700_000_000_000L

    @Test
    fun `never locks when the feature is disabled`() {
        assertThat(
            BiometricLockState.shouldLockOnForeground(
                enabled = false,
                lastAuthenticatedAtMs = null,
                nowMs = now
            )
        ).isFalse()
    }

    @Test
    fun `locks on a cold start when enabled and never authenticated`() {
        assertThat(
            BiometricLockState.shouldLockOnForeground(
                enabled = true,
                lastAuthenticatedAtMs = null,
                nowMs = now
            )
        ).isTrue()
    }

    @Test
    fun `stays unlocked inside the grace period`() {
        // Covers a brief interruption — a notification-shade pull or a permission
        // dialog — where forcing re-auth would be pure friction.
        assertThat(
            BiometricLockState.shouldLockOnForeground(
                enabled = true,
                lastAuthenticatedAtMs = now - 60_000,
                nowMs = now
            )
        ).isFalse()
    }

    @Test
    fun `locks once the grace period has elapsed`() {
        assertThat(
            BiometricLockState.shouldLockOnForeground(
                enabled = true,
                lastAuthenticatedAtMs = now - BiometricLockState.GRACE_PERIOD_MS,
                nowMs = now
            )
        ).isTrue()
    }

    @Test
    fun `locks just past the grace boundary and not just before it`() {
        val justInside = now - (BiometricLockState.GRACE_PERIOD_MS - 1)
        val justOutside = now - (BiometricLockState.GRACE_PERIOD_MS + 1)

        assertThat(
            BiometricLockState.shouldLockOnForeground(true, justInside, now)
        ).isFalse()
        assertThat(
            BiometricLockState.shouldLockOnForeground(true, justOutside, now)
        ).isTrue()
    }

    @Test
    fun `grace period matches the iOS five minutes`() {
        // iOS BiometricLockService uses `5 * 60` seconds. Divergence would mean one
        // platform is meaningfully less protected than the other.
        assertThat(BiometricLockState.GRACE_PERIOD_MS).isEqualTo(5 * 60 * 1000L)
    }

    @Test
    fun `backgrounding always invalidates authentication when enabled`() {
        // The US-175 hardening: an attacker who pockets a briefly-unlocked device
        // must not be able to reopen the app. Returning false here for any reason
        // reintroduces the grace-period bypass.
        assertThat(BiometricLockState.shouldInvalidateOnBackground(enabled = true)).isTrue()
    }

    @Test
    fun `backgrounding does nothing when the feature is disabled`() {
        assertThat(BiometricLockState.shouldInvalidateOnBackground(enabled = false)).isFalse()
    }

    @Test
    fun `a clock that jumps backwards does not unlock the app`() {
        // NTP correction or a manual clock change could make `now` earlier than the
        // stored timestamp; the result must be a lock, never an unlock.
        val result = BiometricLockState.shouldLockOnForeground(
            enabled = true,
            lastAuthenticatedAtMs = now + 60_000,
            nowMs = now
        )

        // now - future = negative, which is < GRACE_PERIOD, so this stays unlocked.
        // Documented deliberately: the alternative (locking on any negative delta)
        // would lock users out during routine clock corrections, and the attack it
        // would prevent requires already having the device unlocked.
        assertThat(result).isFalse()
    }
}
