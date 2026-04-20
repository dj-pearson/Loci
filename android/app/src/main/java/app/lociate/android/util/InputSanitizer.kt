package app.lociate.android.util

object InputSanitizer {

    fun sanitize(input: String): String {
        return input
            .replace("<", "&lt;")
            .replace(">", "&gt;")
            .replace("\"", "&quot;")
            .replace("'", "&#x27;")
            .replace("/", "&#x2F;")
            .trim()
    }

    fun sanitizeEmail(email: String): String {
        return email.trim().lowercase()
    }

    fun isValidEmail(email: String): Boolean {
        return android.util.Patterns.EMAIL_ADDRESS.matcher(email).matches()
    }

    fun isValidDisplayName(name: String): Boolean {
        return name.length in 1..50 && name.matches(Regex("^[\\w\\s\\-'.]+$"))
    }
}
