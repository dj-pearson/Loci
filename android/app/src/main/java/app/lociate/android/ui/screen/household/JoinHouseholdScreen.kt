package app.lociate.android.ui.screen.household

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.GroupAdd
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun JoinHouseholdScreen(
    onBack: () -> Unit,
    onUpgradeClick: () -> Unit,
    viewModel: HouseholdViewModel = hiltViewModel()
) {
    val state by viewModel.uiState.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }
    var inviteCode by remember { mutableStateOf("") }

    LaunchedEffect(state.error) {
        state.error?.let {
            snackbarHostState.showSnackbar(it)
            viewModel.clearError()
        }
    }

    LaunchedEffect(state.joinSuccess) {
        if (state.joinSuccess) {
            snackbarHostState.showSnackbar("Successfully joined household!")
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Join Household") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back")
                    }
                }
            )
        },
        snackbarHost = { SnackbarHost(snackbarHostState) }
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .padding(16.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            Icon(
                Icons.Default.GroupAdd,
                contentDescription = null,
                modifier = Modifier.padding(top = 24.dp),
                tint = MaterialTheme.colorScheme.primary
            )

            Text(
                "Join a Household",
                style = MaterialTheme.typography.headlineMedium
            )

            Text(
                "Enter the invite code shared by the household owner to join their family group.",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center
            )

            if (state.currentTier == app.lociate.android.domain.model.SubscriptionTier.FREE) {
                Card(
                    colors = CardDefaults.cardColors(
                        containerColor = MaterialTheme.colorScheme.tertiaryContainer
                    ),
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Column(modifier = Modifier.padding(16.dp)) {
                        Text("Upgrade Required", style = MaterialTheme.typography.titleSmall)
                        Text(
                            "A Premium or Family plan is required to join a household.",
                            style = MaterialTheme.typography.bodySmall
                        )
                        Button(onClick = onUpgradeClick, modifier = Modifier.padding(top = 8.dp)) {
                            Text("Upgrade")
                        }
                    }
                }
            }

            if (state.joinSuccess) {
                Card(
                    colors = CardDefaults.cardColors(
                        containerColor = MaterialTheme.colorScheme.primaryContainer
                    ),
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Column(
                        modifier = Modifier.padding(16.dp),
                        horizontalAlignment = Alignment.CenterHorizontally
                    ) {
                        Text("Welcome!", style = MaterialTheme.typography.titleMedium)
                        Text(
                            "You've joined ${state.household?.name ?: "the household"}. Shared loci will now appear on your map.",
                            style = MaterialTheme.typography.bodyMedium
                        )
                    }
                }
            } else {
                OutlinedTextField(
                    value = inviteCode,
                    onValueChange = { inviteCode = it.uppercase().take(8) },
                    label = { Text("Invite Code") },
                    placeholder = { Text("e.g., AB12CD34") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                    enabled = state.currentTier != app.lociate.android.domain.model.SubscriptionTier.FREE
                )

                Button(
                    onClick = { viewModel.joinHousehold(inviteCode) },
                    enabled = inviteCode.isNotBlank() && !state.isLoading &&
                        state.currentTier != app.lociate.android.domain.model.SubscriptionTier.FREE,
                    modifier = Modifier.fillMaxWidth()
                ) {
                    if (state.isLoading) {
                        CircularProgressIndicator()
                    } else {
                        Text("Join Household")
                    }
                }
            }
        }
    }
}
