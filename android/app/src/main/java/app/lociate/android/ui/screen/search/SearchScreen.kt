package app.lociate.android.ui.screen.search

import androidx.compose.foundation.clickable
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
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Clear
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SearchBar
import androidx.compose.material3.SearchBarDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import app.lociate.android.domain.model.Locus

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SearchScreen(
    onLocusClick: (String) -> Unit,
    onBack: () -> Unit,
    viewModel: SearchViewModel = hiltViewModel()
) {
    val results by viewModel.results.collectAsState()
    var query by remember { mutableStateOf("") }
    var active by remember { mutableStateOf(true) }

    Column(modifier = Modifier.fillMaxSize()) {
        SearchBar(
            inputField = {
                SearchBarDefaults.InputField(
                    query = query,
                    onQueryChange = {
                        query = it
                        viewModel.search(it)
                    },
                    onSearch = { active = false },
                    expanded = active,
                    onExpandedChange = { active = it },
                    placeholder = { Text("Search loci...") },
                    leadingIcon = {
                        IconButton(onClick = onBack) {
                            Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                        }
                    },
                    trailingIcon = {
                        if (query.isNotEmpty()) {
                            IconButton(onClick = {
                                query = ""
                                viewModel.search("")
                            }) {
                                Icon(Icons.Default.Clear, contentDescription = "Clear")
                            }
                        }
                    }
                )
            },
            expanded = active,
            onExpandedChange = { active = it },
            modifier = Modifier.fillMaxWidth()
        ) {
            LazyColumn {
                items(results, key = { it.id.toString() }) { locus ->
                    SearchResultItem(
                        locus = locus,
                        onClick = { onLocusClick(locus.id.toString()) }
                    )
                }
            }
        }
    }
}

@Composable
private fun SearchResultItem(
    locus: Locus,
    onClick: () -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(
            imageVector = locus.category.icon,
            contentDescription = null,
            tint = locus.category.color,
            modifier = Modifier.size(32.dp)
        )
        Spacer(modifier = Modifier.width(12.dp))
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = locus.locationName ?: "Unknown location",
                style = MaterialTheme.typography.titleMedium,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
            if (locus.transcription.isNotEmpty()) {
                Spacer(modifier = Modifier.height(2.dp))
                Text(
                    text = locus.transcription,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
        }
    }
}
