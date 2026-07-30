package app.lociate.android.ui

import android.os.Bundle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.fragment.app.FragmentActivity
import app.lociate.android.service.BiometricLockService
import app.lociate.android.ui.component.BiometricLockGate
import app.lociate.android.ui.navigation.LociateNavHost
import app.lociate.android.ui.theme.LociateTheme
import dagger.hilt.android.AndroidEntryPoint
import javax.inject.Inject

@AndroidEntryPoint
// US-212: FragmentActivity, not ComponentActivity — BiometricPrompt requires a
// FragmentActivity host. `setContent` works either way, since FragmentActivity is
// itself a ComponentActivity.
class MainActivity : FragmentActivity() {

    @Inject
    lateinit var biometricLockService: BiometricLockService

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()

        // US-212: evaluate the lock before the first composition, so protected
        // content is never briefly visible on a cold start.
        biometricLockService.lockIfNeeded()

        setContent {
            LociateTheme {
                val isLocked by biometricLockService.isLocked.collectAsState()

                Surface(
                    modifier = Modifier.fillMaxSize(),
                    color = MaterialTheme.colorScheme.background
                ) {
                    if (isLocked) {
                        // Covers the app entirely rather than gating navigation — a
                        // navigation-level gate would still render the map behind it.
                        BiometricLockGate(biometricLockService)
                    } else {
                        LociateNavHost()
                    }
                }
            }
        }
    }

    override fun onStart() {
        super.onStart()
        // Returning to the foreground: re-lock unless we are inside the grace period.
        biometricLockService.lockIfNeeded()
    }

    override fun onStop() {
        super.onStop()
        // US-212: lock immediately and discard the grace period, matching the iOS
        // hardening from US-175 — otherwise anyone who picks up a briefly-unlocked
        // device can reopen the app.
        biometricLockService.recordBackgroundTransition()
    }
}
