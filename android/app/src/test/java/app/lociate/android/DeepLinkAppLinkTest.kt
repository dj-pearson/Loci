package app.lociate.android

import android.net.Uri
import app.lociate.android.util.DeepLinkValidator
import com.google.common.truth.Truth.assertThat
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/**
 * US-203: the manifest declared `lociate://locus` while the validator only
 * accepted `loci://locus`, so every deep link the app could receive was rejected.
 * These pin the scheme, host, and path contract shared with iOS.
 */
@RunWith(RobolectricTestRunner::class)
class DeepLinkAppLinkTest {

    private val validId = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"

    @Test
    fun `accepts the canonical lociate scheme`() {
        assertThat(DeepLinkValidator.extractLocusIdFromUri(Uri.parse("lociate://locus/$validId")))
            .isEqualTo(validId)
    }

    @Test
    fun `accepts the legacy loci scheme emitted by the iOS widget`() {
        assertThat(DeepLinkValidator.extractLocusIdFromUri(Uri.parse("loci://locus/$validId")))
            .isEqualTo(validId)
    }

    @Test
    fun `accepts https App Links on the declared paths`() {
        assertThat(
            DeepLinkValidator.extractLocusIdFromUri(Uri.parse("https://lociate.app/locus/$validId"))
        ).isEqualTo(validId)
        assertThat(
            DeepLinkValidator.extractLocusIdFromUri(Uri.parse("https://lociate.app/open/$validId"))
        ).isEqualTo(validId)
        assertThat(
            DeepLinkValidator.extractLocusIdFromUri(
                Uri.parse("https://www.lociate.app/locus/$validId")
            )
        ).isEqualTo(validId)
    }

    @Test
    fun `rejects an https host that is not ours`() {
        assertThat(
            DeepLinkValidator.extractLocusIdFromUri(Uri.parse("https://evil.example/locus/$validId"))
        ).isNull()
    }

    @Test
    fun `rejects an undeclared https path`() {
        assertThat(
            DeepLinkValidator.extractLocusIdFromUri(Uri.parse("https://lociate.app/admin/$validId"))
        ).isNull()
    }

    @Test
    fun `rejects an unknown custom scheme`() {
        assertThat(DeepLinkValidator.extractLocusIdFromUri(Uri.parse("evil://locus/$validId")))
            .isNull()
    }

    @Test
    fun `rejects an unknown host on a custom scheme`() {
        assertThat(DeepLinkValidator.extractLocusIdFromUri(Uri.parse("lociate://admin/$validId")))
            .isNull()
    }

    @Test
    fun `rejects a non-UUID id on every accepted route`() {
        // The injection guard has to run for App Links too, not just the custom scheme.
        assertThat(DeepLinkValidator.extractLocusIdFromUri(Uri.parse("lociate://locus/../../etc/passwd")))
            .isNull()
        assertThat(DeepLinkValidator.extractLocusIdFromUri(Uri.parse("https://lociate.app/locus/not-a-uuid")))
            .isNull()
    }
}
