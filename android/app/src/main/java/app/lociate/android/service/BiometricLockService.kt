package app.lociate.android.service

import android.content.Context
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.fragment.app.FragmentActivity
import app.lociate.android.util.SecurePreferences
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.suspendCancellableCoroutine
import timber.log.Timber
import javax.inject.Inject
import javax.inject.Singleton
import kotlin.coroutines.resume

/**
 * Biometric app lock (US-212).
 *
 * The androidx.biometric dependency was already declared but `BiometricPrompt`
 * was never used anywhere, so the setting iOS offers silently did not exist on
 * Android — the tier table and the Settings screen implied otherwise.
 *
 * The lock *decision* lives in [BiometricLockState] so it can be tested without a
 * device; this class owns only the framework interaction.
 */
@Singleton
class BiometricLockService @Inject constructor(
    private val securePreferences: SecurePreferences
) {

    private val _isLocked = MutableStateFlow(false)
    val isLocked: StateFlow<Boolean> = _isLocked.asStateFlow()

    /** Never persisted: a stored timestamp would survive a reboot and extend the grace period. */
    private var lastAuthenticatedAtMs: Long? = null

    var isEnabled: Boolean
        get() = securePreferences.getBoolean(SecurePreferences.KEY_BIOMETRIC_ENABLED)
        set(value) {
            securePreferences.putBoolean(SecurePreferences.KEY_BIOMETRIC_ENABLED, value)
            if (!value) {
                _isLocked.value = false
                lastAuthenticatedAtMs = null
            }
        }

    // MARK: - Capability

    enum class Capability {
        /** Biometric hardware present and at least one credential enrolled. */
        AVAILABLE,

        /** Hardware present but nothing enrolled — offer device credential instead. */
        NOT_ENROLLED,

        /** No usable hardware. The toggle must stay hidden. */
        UNAVAILABLE,
    }

    fun capability(context: Context): Capability {
        val manager = BiometricManager.from(context)
        // BIOMETRIC_WEAK | DEVICE_CREDENTIAL: a PIN or pattern is an acceptable
        // fallback for an app lock, and requiring STRONG would hide the feature on
        // a large share of devices.
        val authenticators =
            BiometricManager.Authenticators.BIOMETRIC_WEAK or
                BiometricManager.Authenticators.DEVICE_CREDENTIAL

        return when (manager.canAuthenticate(authenticators)) {
            BiometricManager.BIOMETRIC_SUCCESS -> Capability.AVAILABLE
            BiometricManager.BIOMETRIC_ERROR_NONE_ENROLLED -> Capability.NOT_ENROLLED
            else -> Capability.UNAVAILABLE
        }
    }

    /** True when the Settings toggle should be shown at all. */
    fun isSupported(context: Context): Boolean = capability(context) != Capability.UNAVAILABLE

    // MARK: - Authentication

    /**
     * Shows the system prompt and suspends until the user resolves it.
     *
     * Returns false on failure or cancellation rather than throwing: a failed
     * unlock is an expected outcome, not an error condition.
     */
    suspend fun authenticate(activity: FragmentActivity): Boolean =
        suspendCancellableCoroutine { continuation ->
            val executor = androidx.core.content.ContextCompat.getMainExecutor(activity)

            val callback = object : BiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
                    lastAuthenticatedAtMs = System.currentTimeMillis()
                    _isLocked.value = false
                    if (continuation.isActive) continuation.resume(true)
                }

                override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                    Timber.d("Biometric auth error $errorCode: $errString")
                    if (continuation.isActive) continuation.resume(false)
                }

                override fun onAuthenticationFailed() {
                    // A single non-matching attempt; the prompt stays up, so do not
                    // resume here or the caller would see a failure mid-retry.
                    Timber.d("Biometric attempt did not match")
                }
            }

            val prompt = BiometricPrompt(activity, executor, callback)

            val info = BiometricPrompt.PromptInfo.Builder()
                .setTitle(activity.getString(app.lociate.android.R.string.biometric_prompt_title))
                .setSubtitle(activity.getString(app.lociate.android.R.string.biometric_prompt_subtitle))
                // Allowing DEVICE_CREDENTIAL means no negative button may be set —
                // the system supplies the passcode path itself.
                .setAllowedAuthenticators(
                    BiometricManager.Authenticators.BIOMETRIC_WEAK or
                        BiometricManager.Authenticators.DEVICE_CREDENTIAL
                )
                .build()

            prompt.authenticate(info)

            continuation.invokeOnCancellation { prompt.cancelAuthentication() }
        }

    // MARK: - Lifecycle

    /** Called when the app returns to the foreground. */
    fun lockIfNeeded(nowMs: Long = System.currentTimeMillis()) {
        _isLocked.value = BiometricLockState.shouldLockOnForeground(
            enabled = isEnabled,
            lastAuthenticatedAtMs = lastAuthenticatedAtMs,
            nowMs = nowMs
        )
    }

    /**
     * Called when the app goes to the background.
     *
     * Locks immediately and discards the grace period — the same hardening iOS
     * applied in US-175. Leaving the timestamp intact here would let anyone who
     * picks up a briefly-unlocked device reopen the app.
     */
    fun recordBackgroundTransition() {
        if (!BiometricLockState.shouldInvalidateOnBackground(isEnabled)) return
        lastAuthenticatedAtMs = null
        _isLocked.value = true
    }
}
