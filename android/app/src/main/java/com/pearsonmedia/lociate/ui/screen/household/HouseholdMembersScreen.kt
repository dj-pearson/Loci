package com.pearsonmedia.lociate.ui.screen.household

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.ExitToApp
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.RemoveCircleOutline
import androidx.compose.material.icons.filled.Star
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.pearsonmedia.lociate.domain.model.HouseholdMember
import com.pearsonmedia.lociate.domain.model.MemberRole

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HouseholdMembersScreen(
    onBack: () -> Unit,
    viewModel: HouseholdViewModel = hiltViewModel()
) {
    val state by viewModel.uiState.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }
    var showLeaveDialog by remember { mutableStateOf(false) }
    var memberToRemove by remember { mutableStateOf<HouseholdMember?>(null) }
    val context = LocalContext.current

    LaunchedEffect(state.error) {
        state.error?.let {
            snackbarHostState.showSnackbar(it)
            viewModel.clearError()
        }
    }

    if (showLeaveDialog) {
        AlertDialog(
            onDismissRequest = { showLeaveDialog = false },
            title = { Text("Leave Household?") },
            text = { Text("You will no longer see shared loci from this household.") },
            confirmButton = {
                TextButton(onClick = {
                    showLeaveDialog = false
                    viewModel.leaveHousehold()
                    onBack()
                }) { Text("Leave") }
            },
            dismissButton = {
                TextButton(onClick = { showLeaveDialog = false }) { Text("Cancel") }
            }
        )
    }

    memberToRemove?.let { member ->
        AlertDialog(
            onDismissRequest = { memberToRemove = null },
            title = { Text("Remove Member?") },
            text = { Text("Remove ${member.displayName} from the household?") },
            confirmButton = {
                TextButton(onClick = {
                    viewModel.removeMember(member.id)
                    memberToRemove = null
                }) { Text("Remove") }
            },
            dismissButton = {
                TextButton(onClick = { memberToRemove = null }) { Text("Cancel") }
            }
        )
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(state.household?.name ?: "Household") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back")
                    }
                }
            )
        },
        snackbarHost = { SnackbarHost(snackbarHostState) }
    ) { padding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .padding(horizontal = 16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            // Invite code card
            item {
                state.inviteCode?.let { code ->
                    Card(
                        colors = CardDefaults.cardColors(
                            containerColor = MaterialTheme.colorScheme.primaryContainer
                        ),
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(16.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Column(modifier = Modifier.weight(1f)) {
                                Text("Invite Code", style = MaterialTheme.typography.labelMedium)
                                Text(
                                    code,
                                    style = MaterialTheme.typography.headlineSmall,
                                    fontFamily = FontFamily.Monospace
                                )
                            }
                            IconButton(onClick = {
                                val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                                clipboard.setPrimaryClip(ClipData.newPlainText("Invite Code", code))
                            }) {
                                Icon(Icons.Default.ContentCopy, "Copy")
                            }
                        }
                    }
                }
            }

            // Members section header
            item {
                Text(
                    "Members (${state.members.size})",
                    style = MaterialTheme.typography.titleMedium,
                    modifier = Modifier.padding(top = 8.dp)
                )
            }

            // Member list
            items(state.members, key = { it.id }) { member ->
                val isOwner = member.role == MemberRole.OWNER
                val currentUserIsOwner = state.members.any {
                    it.role == MemberRole.OWNER
                }

                Card(modifier = Modifier.fillMaxWidth()) {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(16.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Icon(
                            if (isOwner) Icons.Default.Star else Icons.Default.Person,
                            contentDescription = if (isOwner) "Owner" else "Member",
                            tint = if (isOwner) MaterialTheme.colorScheme.primary
                                else MaterialTheme.colorScheme.onSurfaceVariant
                        )
                        Spacer(Modifier.width(12.dp))
                        Column(modifier = Modifier.weight(1f)) {
                            Text(member.displayName, style = MaterialTheme.typography.bodyLarge)
                            Text(
                                if (isOwner) "Owner" else "Member",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                        if (currentUserIsOwner && !isOwner) {
                            IconButton(onClick = { memberToRemove = member }) {
                                Icon(
                                    Icons.Default.RemoveCircleOutline,
                                    "Remove member",
                                    tint = MaterialTheme.colorScheme.error
                                )
                            }
                        }
                    }
                }
            }

            // Leave button (non-owners only)
            item {
                Spacer(Modifier.height(16.dp))
                val currentUserIsOwner = state.members.any {
                    it.role == MemberRole.OWNER
                }
                if (!currentUserIsOwner) {
                    FilledTonalButton(
                        onClick = { showLeaveDialog = true },
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Icon(Icons.AutoMirrored.Filled.ExitToApp, null)
                        Spacer(Modifier.width(8.dp))
                        Text("Leave Household")
                    }
                }
                Spacer(Modifier.height(32.dp))
            }
        }
    }
}
