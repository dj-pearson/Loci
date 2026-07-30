package app.lociate.android

import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.rule.GrantPermissionRule
import app.lociate.android.ui.MainActivity
import dagger.hilt.android.testing.HiltAndroidRule
import dagger.hilt.android.testing.HiltAndroidTest
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * US-192: minimal proof that the Hilt graph resolves and MainActivity composes.
 *
 * This is deliberately narrow — it catches a broken dependency graph or a
 * Compose navigation crash, which are the failures that make every other
 * instrumented test meaningless. The fuller record-to-list flow is US-209.
 *
 * No network and no Supabase calls: the assertions only touch the bottom
 * navigation bar, which renders from local state.
 */
@HiltAndroidTest
@RunWith(AndroidJUnit4::class)
class AppLaunchSmokeTest {

    @get:Rule(order = 0)
    val hiltRule = HiltAndroidRule(this)

    @get:Rule(order = 1)
    val permissionRule: GrantPermissionRule = GrantPermissionRule.grant(
        android.Manifest.permission.ACCESS_FINE_LOCATION,
        android.Manifest.permission.ACCESS_COARSE_LOCATION,
        android.Manifest.permission.RECORD_AUDIO
    )

    @get:Rule(order = 2)
    val composeRule = createAndroidComposeRule<MainActivity>()

    @Test
    fun appLaunchesAndShowsBottomNavigation() {
        hiltRule.inject()
        composeRule.waitForIdle()

        composeRule.onNodeWithText("Map").assertExists()
        composeRule.onNodeWithText("List").assertExists()
        composeRule.onNodeWithText("Settings").assertExists()
    }
}
