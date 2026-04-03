package com.pearsonmedia.loci.util

import timber.log.Timber
import java.time.Instant

/**
 * Tracks login attempts and enforces exponential backoff lockout policy.
 * Mirrors the iOS LoginAttemptTracker behavior.
 *
 * Lockout policy:
 * - 3 failures: 30 second cooldown
 * - 5 failures: 2 minute cooldown
 * - 8 failures: 15 minute cooldown
 * - 10+ failures: 60 minute cooldown
 */
class LoginAttemptTracker(private val securePreferences: SecurePreferences) {

    data class LockoutState(
        val isLockedOut: Boolean,
        val remainingSeconds: Long,
        val failureCount: Int
    )

    fun checkLockout(email: String): LockoutState {
        val key = keyForEmail(email)
        val failures = securePreferences.getInt("${key}_failures", 0)
        val lockoutUntil = securePreferences.getLong("${key}_lockout_until", 0)

        if (lockoutUntil == 0L || failures < 3) {
            return LockoutState(isLockedOut = false, remainingSeconds = 0, failureCount = failures)
        }

        val now = Instant.now().epochSecond
        val remaining = lockoutUntil - now

        return if (remaining > 0) {
            LockoutState(isLockedOut = true, remainingSeconds = remaining, failureCount = failures)
        } else {
            LockoutState(isLockedOut = false, remainingSeconds = 0, failureCount = failures)
        }
    }

    fun recordFailure(email: String) {
        val key = keyForEmail(email)
        val failures = securePreferences.getInt("${key}_failures", 0) + 1
        securePreferences.putInt("${key}_failures", failures)

        val lockoutDurationSeconds = when {
            failures >= 10 -> 3600L    // 60 minutes
            failures >= 8 -> 900L      // 15 minutes
            failures >= 5 -> 120L      // 2 minutes
            failures >= 3 -> 30L       // 30 seconds
            else -> 0L
        }

        if (lockoutDurationSeconds > 0) {
            val lockoutUntil = Instant.now().epochSecond + lockoutDurationSeconds
            securePreferences.putLong("${key}_lockout_until", lockoutUntil)
            Timber.w("Login locked out for ${lockoutDurationSeconds}s after $failures failures for ${maskEmail(email)}")
        }
    }

    fun recordSuccess(email: String) {
        val key = keyForEmail(email)
        securePreferences.remove("${key}_failures")
        securePreferences.remove("${key}_lockout_until")
        Timber.d("Login attempt counter reset for ${maskEmail(email)}")
    }

    private fun keyForEmail(email: String): String {
        // Use a hash to avoid storing the email directly
        return "login_${email.lowercase().hashCode()}"
    }

    private fun maskEmail(email: String): String {
        val parts = email.split("@")
        if (parts.size != 2) return "***"
        val local = parts[0]
        val masked = if (local.length > 2) {
            "${local.first()}${"*".repeat(local.length - 2)}${local.last()}"
        } else {
            "*".repeat(local.length)
        }
        return "$masked@${parts[1]}"
    }
}
