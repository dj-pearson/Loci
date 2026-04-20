package app.lociate.android.ui.screen.detail

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Archive
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import java.time.ZoneId
import java.time.format.DateTimeFormatter

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LocusDetailScreen(
    locusId: String,
    onBack: () -> Unit,
    viewModel: LocusDetailViewModel = hiltViewModel()
) {
    val locus by viewModel.locus.collectAsState()
    val isPlaying by viewModel.isPlaying.collectAsState()
    val progress by viewModel.playbackProgress.collectAsState()

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(locus?.locationName ?: "Locus Detail") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    IconButton(onClick = { viewModel.showEdit() }) {
                        Icon(Icons.Default.Edit, contentDescription = "Edit")
                    }
                    IconButton(onClick = {
                        viewModel.archive()
                        onBack()
                    }) {
                        Icon(Icons.Default.Archive, contentDescription = "Archive")
                    }
                    IconButton(onClick = {
                        viewModel.delete()
                        onBack()
                    }) {
                        Icon(Icons.Default.Delete, contentDescription = "Delete",
                            tint = MaterialTheme.colorScheme.error)
                    }
                }
            )
        }
    ) { padding ->
        locus?.let { l ->
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding)
                    .padding(16.dp)
                    .verticalScroll(rememberScrollState())
            ) {
                // Category badge
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(
                        imageVector = l.category.icon,
                        contentDescription = l.category.displayName,
                        tint = l.category.color,
                        modifier = Modifier.size(24.dp)
                    )
                    Spacer(modifier = Modifier.width(8.dp))
                    Text(
                        text = l.category.displayName,
                        style = MaterialTheme.typography.labelLarge,
                        color = l.category.color
                    )
                }

                Spacer(modifier = Modifier.height(16.dp))

                // Audio playback
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    elevation = CardDefaults.cardElevation(defaultElevation = 2.dp)
                ) {
                    Column(modifier = Modifier.padding(16.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            IconButton(onClick = { viewModel.playPause() }) {
                                Icon(
                                    if (isPlaying) Icons.Default.Pause else Icons.Default.PlayArrow,
                                    contentDescription = if (isPlaying) "Pause" else "Play",
                                    modifier = Modifier.size(32.dp)
                                )
                            }

                            LinearProgressIndicator(
                                progress = { progress },
                                modifier = Modifier
                                    .weight(1f)
                                    .height(4.dp)
                            )
                        }
                    }
                }

                Spacer(modifier = Modifier.height(24.dp))

                // Transcription
                Text(
                    text = "Transcription",
                    style = MaterialTheme.typography.titleMedium
                )
                Spacer(modifier = Modifier.height(8.dp))
                Text(
                    text = l.transcription.ifEmpty { "No transcription available" },
                    style = MaterialTheme.typography.bodyLarge,
                    color = if (l.transcription.isEmpty()) {
                        MaterialTheme.colorScheme.onSurfaceVariant
                    } else {
                        MaterialTheme.colorScheme.onSurface
                    }
                )

                Spacer(modifier = Modifier.height(24.dp))

                // Metadata
                Text(
                    text = "Details",
                    style = MaterialTheme.typography.titleMedium
                )
                Spacer(modifier = Modifier.height(8.dp))

                val formatter = DateTimeFormatter.ofPattern("MMMM d, yyyy 'at' h:mm a")
                Text(
                    text = "Created: ${l.createdAt.atZone(ZoneId.systemDefault()).format(formatter)}",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Spacer(modifier = Modifier.height(4.dp))
                Text(
                    text = "Location: ${l.locationName ?: "${l.latitude}, ${l.longitude}"}",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )

                if (l.isShared) {
                    Spacer(modifier = Modifier.height(4.dp))
                    Text(
                        text = "Shared with family",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.tertiary
                    )
                }
            }
        }
    }
}
