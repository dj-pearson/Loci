package com.pearsonmedia.lociate

import com.google.common.truth.Truth.assertThat
import com.pearsonmedia.lociate.util.InputSanitizer
import org.junit.Test

class InputSanitizerTest {

    @Test
    fun `sanitize removes XSS script tags`() {
        val input = "<script>alert('xss')</script>"
        val sanitized = InputSanitizer.sanitize(input)
        assertThat(sanitized).doesNotContain("<script>")
        assertThat(sanitized).doesNotContain("</script>")
    }

    @Test
    fun `sanitize trims whitespace`() {
        val input = "  hello world  "
        val sanitized = InputSanitizer.sanitize(input)
        assertThat(sanitized).isEqualTo("hello world")
    }

    @Test
    fun `sanitize escapes HTML entities`() {
        val input = "Tom & Jerry <friends>"
        val sanitized = InputSanitizer.sanitize(input)
        assertThat(sanitized).contains("&lt;")
        assertThat(sanitized).contains("&gt;")
    }

    @Test
    fun `sanitizeEmail lowercases and trims`() {
        val email = "  User@Example.COM  "
        val sanitized = InputSanitizer.sanitizeEmail(email)
        assertThat(sanitized).isEqualTo("user@example.com")
    }

    @Test
    fun `isValidEmail accepts valid emails`() {
        assertThat(InputSanitizer.isValidEmail("user@example.com")).isTrue()
        assertThat(InputSanitizer.isValidEmail("a@b.co")).isTrue()
    }

    @Test
    fun `isValidEmail rejects invalid emails`() {
        assertThat(InputSanitizer.isValidEmail("notanemail")).isFalse()
        assertThat(InputSanitizer.isValidEmail("@example.com")).isFalse()
        assertThat(InputSanitizer.isValidEmail("")).isFalse()
    }

    @Test
    fun `isValidDisplayName accepts valid names`() {
        assertThat(InputSanitizer.isValidDisplayName("John Doe")).isTrue()
        assertThat(InputSanitizer.isValidDisplayName("O'Brien")).isTrue()
        assertThat(InputSanitizer.isValidDisplayName("Mary-Jane")).isTrue()
    }

    @Test
    fun `isValidDisplayName rejects invalid names`() {
        assertThat(InputSanitizer.isValidDisplayName("")).isFalse()
        assertThat(InputSanitizer.isValidDisplayName("a".repeat(51))).isFalse()
    }
}
