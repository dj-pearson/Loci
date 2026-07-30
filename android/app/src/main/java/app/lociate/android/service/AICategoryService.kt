package app.lociate.android.service

import app.lociate.android.domain.model.LocusCategory
import app.lociate.android.domain.model.SubscriptionTier

/**
 * Suggests a category from a transcription (US-216).
 *
 * Android had no categorization at all, so every locus stayed GENERAL while the
 * tier table sold "AI categorization" on Premium and Family.
 *
 * Deliberately the same on-device keyword match the iOS `AICategoryService` uses,
 * with the same keyword table and the same two-match threshold — the two platforms
 * must suggest the same category for the same words, or a household sees the same
 * note filed differently depending on who recorded it. It is also why this needs
 * no network call: nothing is deferred, and it works offline.
 */
object AICategoryService {

    /** Must stay identical to the iOS `categoryKeywords` table. */
    private val CATEGORY_KEYWORDS: Map<LocusCategory, List<String>> = mapOf(
        LocusCategory.FOOD to listOf(
            "grocery", "restaurant", "eat", "cook", "dinner", "lunch", "breakfast",
            "recipe", "kitchen", "food"
        ),
        LocusCategory.SHOPPING to listOf(
            "buy", "price", "sale", "store", "shop", "purchase", "deal", "discount",
            "mall", "market"
        ),
        LocusCategory.PARKING to listOf(
            "park", "lot", "garage", "meter", "parking", "valet", "spot"
        ),
        LocusCategory.HEALTH to listOf(
            "doctor", "pharmacy", "dentist", "hospital", "clinic", "medicine",
            "prescription", "appointment", "health"
        ),
        LocusCategory.TRAVEL to listOf(
            "hotel", "airport", "flight", "trip", "travel", "vacation", "resort",
            "booking", "terminal"
        ),
        LocusCategory.TIP to listOf(
            "try", "recommend", "good", "best", "great", "awesome", "amazing",
            "favorite", "suggestion"
        ),
        LocusCategory.WARNING to listOf(
            "avoid", "careful", "don't", "bad", "terrible", "awful", "dangerous",
            "sketchy", "worst", "broken"
        ),
        LocusCategory.HOME to listOf(
            "plumber", "contractor", "repair", "fix", "renovate", "maintenance",
            "electrician", "leak", "install"
        ),
        LocusCategory.OUTDOOR to listOf(
            "trail", "hike", "camp", "fish", "kayak", "climb", "nature", "mountain",
            "lake", "river"
        ),
    )

    /**
     * A single keyword is too weak a signal — "park the car" should not file a note
     * under Parking on its own. Matches the iOS threshold exactly.
     */
    private const val MINIMUM_MATCHES = 2

    /**
     * @return the suggested category, or [LocusCategory.GENERAL] when the tier does
     *   not include categorization or no category matches strongly enough. The user
     *   can always override the suggestion in the record sheet.
     */
    fun categorize(
        transcription: String,
        tier: SubscriptionTier = SubscriptionTier.PREMIUM
    ): LocusCategory {
        if (!tier.hasAiCategorization) return LocusCategory.GENERAL

        val words = tokenize(transcription.lowercase())

        var best = LocusCategory.GENERAL
        var bestCount = 0

        // Iteration order over a LinkedHashMap is stable, so a tie resolves to the
        // earlier category on both platforms rather than arbitrarily.
        for ((category, keywords) in CATEGORY_KEYWORDS) {
            val matches = keywords.count { it in words }
            if (matches >= MINIMUM_MATCHES && matches > bestCount) {
                bestCount = matches
                best = category
            }
        }

        return best
    }

    /**
     * Splits on non-alphanumerics, keeping apostrophes so "don't" survives as one
     * token — it is a Warning keyword. Mirrors the iOS tokenizer.
     */
    internal fun tokenize(text: String): Set<String> {
        val words = mutableSetOf<String>()
        val current = StringBuilder()

        for (character in text) {
            if (character.isLetterOrDigit() || character == '\'') {
                current.append(character)
            } else if (current.isNotEmpty()) {
                words.add(current.toString())
                current.clear()
            }
        }
        if (current.isNotEmpty()) words.add(current.toString())

        return words
    }
}
