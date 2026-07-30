package app.lociate.android.service

/**
 * The lock decision, extracted as a pure function so it is unit-testable on the
 * JVM without a `BiometricPrompt` or an Activity (US-212).
 *
 * Mirrors the iOS `BiometricLockService` exactly. The behaviour that matters is
 * the one the 2026-04 audit forced on iOS (US-175): backgrounding locks
 * *immediately* and discards the grace period, so an attacker who pockets a
 * briefly-unlocked device cannot reopen the app. The grace period survives only
 * brief `onStop`-free interruptions such as a notification-shade pull.
 */
object BiometricLockState {

    /** Matches the iOS grace period. Divergence here is a security difference. */
    const val GRACE_PERIOD_MS: Long = 5 * 60 * 1000

    /**
     * @param enabled whether the user turned the lock on
     * @param lastAuthenticatedAtMs when the user last authenticated, or null if
     *   never, or if a background transition invalidated it
     * @param nowMs current time
     */
    fun shouldLockOnForeground(
        enabled: Boolean,
        lastAuthenticatedAtMs: Long?,
        nowMs: Long
    ): Boolean {
        if (!enabled) return false
        if (lastAuthenticatedAtMs == null) return true
        return nowMs - lastAuthenticatedAtMs >= GRACE_PERIOD_MS
    }

    /**
     * Whether a background transition should invalidate the stored authentication.
     *
     * Always true when the lock is enabled — that is the point. Returning false
     * here for any reason reintroduces the grace-period bypass.
     */
    fun shouldInvalidateOnBackground(enabled: Boolean): Boolean = enabled
}
