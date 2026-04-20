package app.lociate.android

import com.google.common.truth.Truth.assertThat
import app.lociate.android.domain.model.LocusCategory
import org.junit.Test

class LocusCategoryTest {

    @Test
    fun `fromString returns correct category`() {
        assertThat(LocusCategory.fromString("FOOD")).isEqualTo(LocusCategory.FOOD)
        assertThat(LocusCategory.fromString("food")).isEqualTo(LocusCategory.FOOD)
        assertThat(LocusCategory.fromString("Food")).isEqualTo(LocusCategory.FOOD)
    }

    @Test
    fun `fromString returns GENERAL for unknown`() {
        assertThat(LocusCategory.fromString("unknown")).isEqualTo(LocusCategory.GENERAL)
        assertThat(LocusCategory.fromString("")).isEqualTo(LocusCategory.GENERAL)
    }

    @Test
    fun `all categories have display names`() {
        LocusCategory.entries.forEach { category ->
            assertThat(category.displayName).isNotEmpty()
        }
    }

    @Test
    fun `all 10 categories exist`() {
        assertThat(LocusCategory.entries).hasSize(10)
    }
}
