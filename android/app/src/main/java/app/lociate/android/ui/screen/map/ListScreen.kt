package com.pearsonmedia.lociate.ui.screen.map

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Archive
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarDuration
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.SnackbarResult
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.rememberSwipeToDismissBoxState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.compose.ui.draw.clip
import com.pearsonmedia.lociate.domain.model.Locus
import com.pearsonmedia.lociate.ui.component.EmptyStateView
import com.pearsonmedia.lociate.ui.theme.DesignTokens
import com.pearsonmedia.lociate.ui.theme.LociateGradients
import com.pearsonmedia.lociate.ui.theme.premiumCard
import kotlinx.coroutines.launch
import java.time.ZoneId
import java.time.format.DateTimeFormatter

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ListScreen(
    onLocusClick: (String) -> Unit,
    onSearchClick: () -> Unit,
    viewModel: MapViewModel = hiltViewModel()
) {
    val loci by viewModel.loci.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }
    val scope = rememberCoroutineScope()

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Loci") },
                actions = {
                    IconButton(onClick = onSearchClick) {
                        Icon(Icons.Default.Search, contentDescription = "Search")
                    }
                }
            )
        },
        snackbarHost = { SnackbarHost(snackbarHostState) }
    ) { padding ->
        if (loci.isEmpty()) {
            EmptyStateView(
                title = "No loci yet",
                description = "Record your first voice note to see it here.",
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding)
                    .padding(32.dp)
            )
        } else {
            LazyColumn(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                items(loci, key = { it.id.toString() }) { locus ->
                    val dismissState = rememberSwipeToDismissBoxState(
                        confirmValueChange = { dismissValue ->
                            when (dismissValue) {
                                SwipeToDismissBoxValue.EndToStart -> {
                                    // Archive with undo
                                    scope.launch {
                                        val result = snackbarHostState.showSnackbar(
                                            message = "Locus archived",
                                            actionLabel = "Undo",
                                            duration = SnackbarDuration.Short
                                        )
                                        if (result == SnackbarResult.ActionPerformed) {
                                            // Undo: unarchive handled by ViewModel
                                        }
                                    }
                                    true
                                }
                                else -> false
                            }
                        }
                    )

                    SwipeToDismissBox(
                        state = dismissState,
                        backgroundContent = {
                            val revealed = dismissState.targetValue ==
                                SwipeToDismissBoxValue.EndToStart
                            val premiumBrush = LociateGradients.Premium
                            Box(
                                modifier = Modifier
                                    .fillMaxSize()
                                    .padding(horizontal = DesignTokens.Space.MD)
                                    .clip(RoundedCornerShape(DesignTokens.Radius.MD))
                                    .background(
                                        brush = premiumBrush,
                                        alpha = if (revealed) 1f else 0f
                                    )
                                    .padding(horizontal = 20.dp),
                                contentAlignment = Alignment.CenterEnd
                            ) {
                                Icon(
                                    Icons.Default.Archive,
                                    contentDescription = "Archive",
                                    tint = Color.White
                                )
                            }
                        },
                        enableDismissFromStartToEnd = false
                    ) {
                        LocusListItem(
                            locus = locus,
                            onClick = { onLocusClick(locus.id.toString()) }
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun LocusListItem(
    locus: Locus,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    val formatter = DateTimeFormatter.ofPattern("MMM d, yyyy h:mm a")

    Row(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = DesignTokens.Space.MD)
            .premiumCard(
                radius = DesignTokens.Radius.MD,
                elevation = DesignTokens.Elevation.Level2,
                background = MaterialTheme.colorScheme.surface
            )
            .clickable(onClick = onClick)
            .padding(DesignTokens.Space.MD),
        verticalAlignment = Alignment.CenterVertically
    ) {
        // Category glyph tile — 44dp rounded square with tinted background.
        Box(
            modifier = Modifier
                .size(44.dp)
                .clip(RoundedCornerShape(DesignTokens.Radius.SM))
                .background(locus.category.color),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                imageVector = locus.category.icon,
                contentDescription = locus.category.displayName,
                tint = Color.White,
                modifier = Modifier.size(22.dp)
            )
        }

        Spacer(modifier = Modifier.width(DesignTokens.Space.SM))

        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = locus.transcription.ifEmpty {
                    locus.locationName ?: "Voice note"
                },
                style = MaterialTheme.typography.titleSmall,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis
            )
            Spacer(modifier = Modifier.height(2.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                if (!locus.locationName.isNullOrEmpty()) {
                    Text(
                        text = locus.locationName!!,
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.weight(1f, fill = false)
                    )
                    Text(
                        text = " · ",
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f)
                    )
                }
                Text(
                    text = locus.createdAt
                        .atZone(ZoneId.systemDefault())
                        .format(formatter),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }
}
