package com.pearsonmedia.lociate.util

/**
 * Password strength validation matching iOS PasswordValidator.
 * Enforces minimum complexity and blocks common passwords.
 */
object PasswordValidator {

    enum class Strength {
        WEAK, FAIR, GOOD, STRONG
    }

    data class Requirements(
        val minLength: Boolean,
        val hasUppercase: Boolean,
        val hasLowercase: Boolean,
        val hasDigit: Boolean,
        val hasSpecialChar: Boolean,
        val isLongEnough: Boolean, // 12+ chars for strong
        val notCommon: Boolean
    )

    fun evaluate(password: String): Pair<Strength, Requirements> {
        val requirements = Requirements(
            minLength = password.length >= 8,
            hasUppercase = password.any { it.isUpperCase() },
            hasLowercase = password.any { it.isLowerCase() },
            hasDigit = password.any { it.isDigit() },
            hasSpecialChar = password.any { !it.isLetterOrDigit() },
            isLongEnough = password.length >= 12,
            notCommon = !COMMON_PASSWORDS.contains(password.lowercase())
        )

        val strength = when {
            !requirements.notCommon -> Strength.WEAK
            !requirements.minLength -> Strength.WEAK
            requirements.isLongEnough && requirements.hasUppercase &&
                    requirements.hasLowercase && requirements.hasDigit &&
                    requirements.hasSpecialChar -> Strength.STRONG
            requirements.hasUppercase && requirements.hasLowercase &&
                    requirements.hasDigit && requirements.hasSpecialChar -> Strength.GOOD
            requirements.hasUppercase && requirements.hasLowercase &&
                    requirements.hasDigit -> Strength.FAIR
            else -> Strength.WEAK
        }

        return strength to requirements
    }

    fun meetsMinimum(password: String): Boolean {
        val (strength, _) = evaluate(password)
        return strength >= Strength.FAIR
    }

    private val COMMON_PASSWORDS = setOf(
        "password", "123456", "12345678", "qwerty", "abc123",
        "monkey", "1234567", "letmein", "trustno1", "dragon",
        "baseball", "iloveyou", "master", "sunshine", "ashley",
        "michael", "shadow", "123123", "654321", "superman",
        "qazwsx", "michael", "football", "password1", "password123",
        "batman", "login", "starwars", "whatever", "passw0rd",
        "hello", "charlie", "donald", "admin", "welcome",
        "666666", "1234567890", "loveme", "000000", "access",
        "pepper", "princess", "freedom", "thunder", "ginger",
        "trustme", "summer", "winter", "ranger", "harley",
        "121212", "flower", "hottie", "loveyou", "zaq1zaq1"
    )
}
