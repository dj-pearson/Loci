package com.pearsonmedia.loci.ui.screen.map

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.pearsonmedia.loci.domain.model.LocusCategory
import com.pearsonmedia.loci.ui.component.CategoryFilterChips
import com.pearsonmedia.loci.ui.component.EmptyStateView
import com.pearsonmedia.loci.ui.component.LociMapView

@Composable
fun MapScreen(
    onRecordClick: () -> Unit,
    onLocusClick: (String) -> Unit,
    onSearchClick: () -> Unit,
    viewModel: MapViewModel = hiltViewModel()
) {
    val loci by viewModel.loci.collectAsState()
    val selectedCategory by viewModel.selectedCategory.collectAsState()
    val activeCount by viewModel.activeCount.collectAsState()

    Box(modifier = Modifier.fillMaxSize()) {
        if (loci.isEmpty() && selectedCategory == null) {
            EmptyStateView(
                title = "No loci yet",
                description = "Tap the mic button to pin your first voice note to this location.",
                modifier = Modifier.align(Alignment.Center)
            )
        } else {
            Column(modifier = Modifier.fillMaxSize()) {
                CategoryFilterChips(
                    selectedCategory = selectedCategory,
                    onCategorySelected = { viewModel.selectCategory(it) },
                    modifier = Modifier.fillMaxWidth()
                )

                LociMapView(
                    loci = loci,
                    onLocusClick = onLocusClick,
                    modifier = Modifier.weight(1f)
                )
            }
        }

        // Search button
        IconButton(
            onClick = onSearchClick,
            modifier = Modifier
                .align(Alignment.TopEnd)
                .padding(16.dp)
        ) {
            Icon(
                Icons.Default.Search,
                contentDescription = "Search",
                tint = MaterialTheme.colorScheme.onSurface
            )
        }

        // Record FAB
        FloatingActionButton(
            onClick = onRecordClick,
            containerColor = MaterialTheme.colorScheme.primary,
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .padding(bottom = 16.dp)
                .size(72.dp)
        ) {
            Icon(
                Icons.Default.Mic,
                contentDescription = "Record a voice note",
                modifier = Modifier.size(32.dp),
                tint = MaterialTheme.colorScheme.onPrimary
            )
        }
    }
}
