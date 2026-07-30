package app.lociate.android

import app.lociate.android.util.CrashReporting
import com.google.common.truth.Truth.assertThat
import org.junit.Test

/**
 * US-199: crash reporting must never become a data-leak channel. A voice note's
 * transcription and the coordinate it is pinned to are the two most sensitive
 * things this app holds, and exception messages routinely interpolate both.
 */
class CrashReportingScrubTest {

    @Test
    fun `redacts a decimal coordinate at map precision`() {
        val scrubbed = CrashReporting.scrubText(
            "Failed to geocode 40.760779, -111.891047 after 3 retries"
        )

        assertThat(scrubbed).doesNotContain("40.760779")
        assertThat(scrubbed).doesNotContain("-111.891047")
        assertThat(scrubbed).contains("[redacted]")
        // The surrounding diagnostic text is what makes the report useful.
        assertThat(scrubbed).contains("Failed to geocode")
        assertThat(scrubbed).contains("after 3 retries")
    }

    @Test
    fun `redacts email addresses`() {
        val scrubbed = CrashReporting.scrubText("Sign-in failed for user@example.com")

        assertThat(scrubbed).doesNotContain("user@example.com")
        assertThat(scrubbed).contains("Sign-in failed for")
    }

    @Test
    fun `redacts every occurrence, not just the first`() {
        val scrubbed = CrashReporting.scrubText(
            "path 40.1234 to 41.5678 for a@b.com and c@d.com"
        )

        assertThat(scrubbed).doesNotContain("40.1234")
        assertThat(scrubbed).doesNotContain("41.5678")
        assertThat(scrubbed).doesNotContain("a@b.com")
        assertThat(scrubbed).doesNotContain("c@d.com")
    }

    @Test
    fun `leaves low-precision numbers alone`() {
        // Version strings, durations, and counts are diagnostic, not locations —
        // over-redacting would make reports useless.
        val text = "Timed out after 1.5s on attempt 2 of 3 (build 1.0.0)"

        assertThat(CrashReporting.scrubText(text)).isEqualTo(text)
    }

    @Test
    fun `leaves text with nothing sensitive unchanged`() {
        val text = "Room migration from version 1 to 2 failed: table loci not found"

        assertThat(CrashReporting.scrubText(text)).isEqualTo(text)
    }

    @Test
    fun `handles empty input`() {
        assertThat(CrashReporting.scrubText("")).isEmpty()
    }
}
