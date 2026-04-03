package com.pearsonmedia.loci

import android.net.Uri
import com.google.common.truth.Truth.assertThat
import com.pearsonmedia.loci.util.DeepLinkValidator
import io.mockk.every
import io.mockk.mockk
import io.mockk.mockkStatic
import org.junit.Before
import org.junit.Test

class DeepLinkValidatorTest {

    @Before
    fun setup() {
        // Mock Uri.parse for unit tests (no Android framework)
        mockkStatic(Uri::class)
    }

    @Test
    fun `valid loci scheme and UUID is accepted`() {
        val uri = mockUri("loci", "locus", "550e8400-e29b-41d4-a716-446655440000")
        val result = DeepLinkValidator.extractLocusIdFromUri(uri)
        assertThat(result).isEqualTo("550e8400-e29b-41d4-a716-446655440000")
    }

    @Test
    fun `wrong scheme is rejected`() {
        val uri = mockUri("https", "locus", "550e8400-e29b-41d4-a716-446655440000")
        val result = DeepLinkValidator.extractLocusIdFromUri(uri)
        assertThat(result).isNull()
    }

    @Test
    fun `wrong host is rejected`() {
        val uri = mockUri("loci", "evil", "550e8400-e29b-41d4-a716-446655440000")
        val result = DeepLinkValidator.extractLocusIdFromUri(uri)
        assertThat(result).isNull()
    }

    @Test
    fun `invalid UUID format is rejected`() {
        val uri = mockUri("loci", "locus", "not-a-uuid")
        val result = DeepLinkValidator.extractLocusIdFromUri(uri)
        assertThat(result).isNull()
    }

    @Test
    fun `path traversal attempt is rejected`() {
        val uri = mockUri("loci", "locus", "../../../etc/passwd")
        val result = DeepLinkValidator.extractLocusIdFromUri(uri)
        assertThat(result).isNull()
    }

    @Test
    fun `null intent returns null`() {
        val result = DeepLinkValidator.extractLocusId(null)
        assertThat(result).isNull()
    }

    private fun mockUri(scheme: String, host: String, lastSegment: String): Uri {
        val uri = mockk<Uri>()
        every { uri.scheme } returns scheme
        every { uri.host } returns host
        every { uri.lastPathSegment } returns lastSegment
        return uri
    }
}
