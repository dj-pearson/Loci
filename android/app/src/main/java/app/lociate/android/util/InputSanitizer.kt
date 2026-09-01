package app.lociate.android.util

object InputSanitizer {

    /**
     * The same expression as `android.util.Patterns.EMAIL_ADDRESS`, inlined verbatim
     * from AOSP.
     *
     * [isValidEmail] used to call that framework constant directly, which is null on a
     * plain JVM unit test — so both email tests failed with a NullPointerException
     * rather than an assertion. Nothing about validating an email needs the Android
     * framework, and a pure-Kotlin regex is testable without Robolectric.
     */
    private val EMAIL_ADDRESS = Regex(
        "[a-zA-Z0-9+._%\\-+]{1,256}" +
            "@" +
            "[a-zA-Z0-9][a-zA-Z0-9\\-]{0,64}" +
            "(" +
            "\\." +
            "[a-zA-Z0-9][a-zA-Z0-9\\-]{0,25}" +
            ")+"
    )

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
        return EMAIL_ADDRESS.matches(email)
    }

    fun isValidDisplayName(name: String): Boolean {
        return name.length in 1..50 && name.matches(Regex("^[\\w\\s\\-'.]+$"))
    }
}
