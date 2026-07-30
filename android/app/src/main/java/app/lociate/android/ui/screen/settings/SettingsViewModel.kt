package app.lociate.android.ui.screen.settings

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import app.lociate.android.service.BiometricLockService
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import javax.inject.Inject

/**
 * Backs the Settings screen's security section (US-212).
 *
 * The biometric toggle was previously local `remember { mutableStateOf(false) }`
 * state — it reset on every recomposition and persisted nothing, so the setting
 * the tier table and Settings screen advertised did not exist.
 */
@HiltViewModel
class SettingsViewModel @Inject constructor(
    application: Application,
    private val biometricLockService: BiometricLockService
) : AndroidViewModel(application) {

    data class SecurityState(
        /** False hides the toggle entirely — no usable hardware or screen lock. */
        val isBiometricSupported: Boolean = false,
        /** False means the user must enrol a credential in system settings first. */
        val isBiometricEnrolled: Boolean = false,
        val isBiometricEnabled: Boolean = false,
    )

    private val _securityState = MutableStateFlow(readSecurityState())
    val securityState: StateFlow<SecurityState> = _securityState.asStateFlow()

    fun setBiometricLockEnabled(enabled: Boolean) {
        biometricLockService.isEnabled = enabled
        _securityState.value = readSecurityState()
    }

    /** Re-reads capability, which can change while the app is backgrounded (US-212). */
    fun refreshSecurityState() {
        _securityState.value = readSecurityState()
    }

    private fun readSecurityState(): SecurityState {
        val context = getApplication<Application>()
        val capability = biometricLockService.capability(context)
        return SecurityState(
            isBiometricSupported = capability != BiometricLockService.Capability.UNAVAILABLE,
            isBiometricEnrolled = capability == BiometricLockService.Capability.AVAILABLE,
            isBiometricEnabled = biometricLockService.isEnabled,
        )
    }
}
