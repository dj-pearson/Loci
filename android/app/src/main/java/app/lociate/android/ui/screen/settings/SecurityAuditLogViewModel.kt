package app.lociate.android.ui.screen.settings

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import app.lociate.android.data.local.entity.AuditLogEntity
import app.lociate.android.service.SecurityAuditEvent
import app.lociate.android.service.SecurityAuditLogger
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.stateIn
import javax.inject.Inject

@HiltViewModel
class SecurityAuditLogViewModel @Inject constructor(
    securityAuditLogger: SecurityAuditLogger
) : ViewModel() {

    val entries: StateFlow<List<AuditLogEntity>> = securityAuditLogger
        .observeRecent()
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

    /**
     * Human-readable label for a stored raw value.
     *
     * Falls back to the raw value rather than dropping the row: an entry written by
     * a newer build must still be visible, not silently hidden.
     */
    fun displayName(eventType: String): String =
        when (SecurityAuditEvent.entries.find { it.rawValue == eventType }) {
            SecurityAuditEvent.SIGN_IN_SUCCESS -> "Signed in"
            SecurityAuditEvent.SIGN_IN_FAILURE -> "Failed sign-in attempt"
            SecurityAuditEvent.SIGN_UP -> "Account created"
            SecurityAuditEvent.SIGN_OUT -> "Signed out"
            SecurityAuditEvent.PASSWORD_RESET_REQUEST -> "Password reset requested"
            SecurityAuditEvent.SESSION_EXPIRED -> "Session expired"
            SecurityAuditEvent.ACCOUNT_DELETED -> "Account deleted"
            SecurityAuditEvent.BIOMETRIC_UNLOCK -> "Unlocked with biometrics"
            SecurityAuditEvent.BIOMETRIC_FAILURE -> "Biometric unlock failed"
            null -> eventType
        }
}
