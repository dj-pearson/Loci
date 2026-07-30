package app.lociate.android.ui.screen.settings

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import app.lociate.android.R
import java.text.DateFormat
import java.util.Date

/**
 * Read-only audit log viewer (US-216), mirroring the iOS `SecurityAuditLogView`.
 *
 * Read-only on purpose: a log the user can edit is not an audit trail. Entries hold
 * only a hashed email, so nothing here re-exposes an address.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SecurityAuditLogScreen(
    viewModel: SecurityAuditLogViewModel = hiltViewModel()
) {
    val entries by viewModel.entries.collectAsState()

    Column(modifier = Modifier.fillMaxSize()) {
        TopAppBar(title = { Text(stringResource(R.string.security_audit_log)) })

        if (entries.isEmpty()) {
            Text(
                text = stringResource(R.string.security_audit_log_empty),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(24.dp)
            )
            return@Column
        }

        LazyColumn(modifier = Modifier.fillMaxSize()) {
            items(entries, key = { it.id }) { entry ->
                Column(modifier = Modifier.fillMaxWidth().padding(16.dp)) {
                    Text(
                        text = viewModel.displayName(entry.eventType),
                        style = MaterialTheme.typography.bodyLarge
                    )
                    Text(
                        text = DateFormat.getDateTimeInstance(
                            DateFormat.MEDIUM, DateFormat.SHORT
                        ).format(Date(entry.timestamp)),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    Text(
                        text = "${entry.deviceInfo} · ${entry.appVersion}",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                HorizontalDivider()
            }
        }
    }
}
