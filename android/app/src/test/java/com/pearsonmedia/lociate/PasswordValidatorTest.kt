package com.pearsonmedia.lociate

import com.google.common.truth.Truth.assertThat
import com.pearsonmedia.lociate.util.PasswordValidator
import org.junit.Test

class PasswordValidatorTest {

    @Test
    fun `weak password is detected`() {
        val (strength, _) = PasswordValidator.evaluate("abc")
        assertThat(strength).isEqualTo(PasswordValidator.Strength.WEAK)
    }

    @Test
    fun `common password is always weak`() {
        val (strength, _) = PasswordValidator.evaluate("password123")
        assertThat(strength).isEqualTo(PasswordValidator.Strength.WEAK)
    }

    @Test
    fun `fair password meets minimum`() {
        val (strength, _) = PasswordValidator.evaluate("MyPass12")
        assertThat(strength).isAtLeast(PasswordValidator.Strength.FAIR)
        assertThat(PasswordValidator.meetsMinimum("MyPass12")).isTrue()
    }

    @Test
    fun `strong password detected`() {
        val (strength, requirements) = PasswordValidator.evaluate("MyStr0ng!Pass99")
        assertThat(strength).isEqualTo(PasswordValidator.Strength.STRONG)
        assertThat(requirements.isLongEnough).isTrue()
        assertThat(requirements.hasSpecialChar).isTrue()
        assertThat(requirements.hasUppercase).isTrue()
        assertThat(requirements.hasLowercase).isTrue()
        assertThat(requirements.hasDigit).isTrue()
    }

    @Test
    fun `short password does not meet minimum`() {
        assertThat(PasswordValidator.meetsMinimum("Ab1!")).isFalse()
    }

    @Test
    fun `password without uppercase is weak`() {
        val (strength, _) = PasswordValidator.evaluate("alllowercase123")
        assertThat(strength).isEqualTo(PasswordValidator.Strength.WEAK)
    }

    @Test
    fun `requirements track individual checks`() {
        val (_, requirements) = PasswordValidator.evaluate("Hello123")
        assertThat(requirements.minLength).isTrue()
        assertThat(requirements.hasUppercase).isTrue()
        assertThat(requirements.hasLowercase).isTrue()
        assertThat(requirements.hasDigit).isTrue()
        assertThat(requirements.hasSpecialChar).isFalse()
        assertThat(requirements.isLongEnough).isFalse()
    }
}
