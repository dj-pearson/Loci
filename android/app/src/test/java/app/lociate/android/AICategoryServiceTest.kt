package app.lociate.android

import app.lociate.android.domain.model.LocusCategory
import app.lociate.android.domain.model.SubscriptionTier
import app.lociate.android.service.AICategoryService
import com.google.common.truth.Truth.assertThat
import org.junit.Test

/**
 * US-216: Android had no categorization, so every locus stayed GENERAL while the
 * tier table sold "AI categorization" on Premium and Family.
 *
 * The keyword table and threshold must match iOS exactly — otherwise a household
 * sees the same note filed differently depending on who recorded it.
 */
class AICategoryServiceTest {

    @Test
    fun `free tier gets no suggestion`() {
        // Two FOOD keywords present, but the tier does not include the feature.
        val category = AICategoryService.categorize(
            "grocery store has a great restaurant",
            SubscriptionTier.FREE
        )

        assertThat(category).isEqualTo(LocusCategory.GENERAL)
    }

    @Test
    fun `paid tiers get suggestions`() {
        for (tier in listOf(SubscriptionTier.PREMIUM, SubscriptionTier.FAMILY)) {
            assertThat(
                AICategoryService.categorize("the restaurant food was great", tier)
            ).isEqualTo(LocusCategory.FOOD)
        }
    }

    @Test
    fun `a single keyword is not enough`() {
        // "park the car outside" has one PARKING keyword. Acting on one match would
        // misfile ordinary sentences constantly.
        assertThat(AICategoryService.categorize("park the car outside"))
            .isEqualTo(LocusCategory.GENERAL)
    }

    @Test
    fun `two keywords are enough`() {
        assertThat(AICategoryService.categorize("the parking garage is full"))
            .isEqualTo(LocusCategory.PARKING)
    }

    @Test
    fun `the strongest match wins`() {
        // One SHOPPING keyword ("store") against three FOOD keywords.
        assertThat(
            AICategoryService.categorize("store the recipe, good restaurant food here")
        ).isEqualTo(LocusCategory.FOOD)
    }

    @Test
    fun `matching is case insensitive`() {
        assertThat(AICategoryService.categorize("DOCTOR and PHARMACY nearby"))
            .isEqualTo(LocusCategory.HEALTH)
    }

    @Test
    fun `an empty transcription yields general`() {
        assertThat(AICategoryService.categorize("")).isEqualTo(LocusCategory.GENERAL)
    }

    @Test
    fun `keywords must be whole words, not substrings`() {
        // "parkour" contains "park" but is not about parking. The tokenizer splits on
        // non-alphanumerics, so substring matches cannot happen.
        assertThat(AICategoryService.categorize("parkour and parkland"))
            .isEqualTo(LocusCategory.GENERAL)
    }

    @Test
    fun `the tokenizer keeps apostrophes so don't survives as one token`() {
        // "don't" is a WARNING keyword; splitting on the apostrophe would lose it.
        assertThat(AICategoryService.tokenize("don't go, it's bad")).contains("don't")
        assertThat(AICategoryService.categorize("don't go here, it's bad"))
            .isEqualTo(LocusCategory.WARNING)
    }

    @Test
    fun `punctuation does not prevent a match`() {
        assertThat(AICategoryService.categorize("Trail, hike — nature!"))
            .isEqualTo(LocusCategory.OUTDOOR)
    }

    @Test
    fun `every non-general category is reachable`() {
        // Guards against a typo in the keyword table making a category dead.
        val expectations = mapOf(
            "restaurant food" to LocusCategory.FOOD,
            "buy at the store" to LocusCategory.SHOPPING,
            "parking garage" to LocusCategory.PARKING,
            "doctor pharmacy" to LocusCategory.HEALTH,
            "hotel airport" to LocusCategory.TRAVEL,
            "try the best" to LocusCategory.TIP,
            "avoid, dangerous" to LocusCategory.WARNING,
            "plumber repair" to LocusCategory.HOME,
            "trail hike" to LocusCategory.OUTDOOR,
        )

        for ((text, expected) in expectations) {
            assertThat(AICategoryService.categorize(text)).isEqualTo(expected)
        }
    }
}
