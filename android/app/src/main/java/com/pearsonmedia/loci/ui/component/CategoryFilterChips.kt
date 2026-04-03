package com.pearsonmedia.loci.ui.component

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.pearsonmedia.loci.domain.model.LocusCategory

@Composable
fun CategoryFilterChips(
    selectedCategory: LocusCategory?,
    onCategorySelected: (LocusCategory?) -> Unit,
    modifier: Modifier = Modifier
) {
    Row(
        modifier = modifier
            .horizontalScroll(rememberScrollState())
            .padding(horizontal = 16.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        FilterChip(
            selected = selectedCategory == null,
            onClick = { onCategorySelected(null) },
            label = { Text("All") }
        )

        LocusCategory.entries.forEach { category ->
            FilterChip(
                selected = selectedCategory == category,
                onClick = {
                    onCategorySelected(if (selectedCategory == category) null else category)
                },
                label = { Text(category.displayName) },
                leadingIcon = {
                    Icon(
                        imageVector = category.icon,
                        contentDescription = null,
                        modifier = Modifier.size(18.dp),
                        tint = category.color
                    )
                },
                colors = FilterChipDefaults.filterChipColors()
            )
        }
    }
}
