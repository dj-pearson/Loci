package app.lociate.android

import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.rule.GrantPermissionRule
import app.lociate.android.data.local.dao.LocusDao
import app.lociate.android.data.local.entity.LocusEntity
import app.lociate.android.ui.MainActivity
import dagger.hilt.android.testing.HiltAndroidRule
import dagger.hilt.android.testing.HiltAndroidTest
import kotlinx.coroutines.runBlocking
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.util.UUID
import javax.inject.Inject

/**
 * US-209: one end-to-end proof that a saved locus reaches the list screen.
 *
 * Deliberately seeds the database directly rather than driving the microphone: an
 * instrumented test cannot produce real speech, and mocking the recorder would only
 * test the mock. What this does cover is the part that actually breaks in practice
 * — the Hilt graph, the Room query, the Flow plumbing into Compose, and navigation
 * between tabs.
 *
 * No network and no Supabase calls.
 */
@HiltAndroidTest
@RunWith(AndroidJUnit4::class)
class RecordToListSmokeTest {

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

    @Inject
    lateinit var locusDao: LocusDao

    private val transcription = "smoke test spare key under the mat"

    @Before
    fun setUp() {
        hiltRule.inject()
    }

    @Test
    fun aSavedLocusAppearsOnTheListScreen() {
        runBlocking {
            locusDao.insert(
                LocusEntity(
                    id = UUID.randomUUID().toString(),
                    latitude = 40.7608,
                    longitude = -111.8910,
                    locationName = "Smoke Test Location",
                    audioFilePath = "/data/local/tmp/smoke.m4a",
                    transcription = transcription,
                    category = "HOME",
                    createdAt = System.currentTimeMillis(),
                    updatedAt = System.currentTimeMillis(),
                )
            )
        }

        composeRule.waitForIdle()

        // Navigate to the list tab — this is where a broken Flow or a Hilt graph
        // failure shows up.
        composeRule.onNodeWithText("List").performClick()
        composeRule.waitForIdle()

        // Poll rather than assert immediately: the list is fed by a Room Flow, so
        // the row appears a frame or two after navigation.
        composeRule.waitUntil(timeoutMillis = 5_000) {
            runCatching {
                composeRule
                    .onAllNodesWithText("Smoke Test Location", substring = true)
                    .fetchSemanticsNodes()
                    .isNotEmpty()
            }.getOrDefault(false)
        }

        composeRule.onNodeWithText("Smoke Test Location", substring = true).assertExists()
    }
}
