package com.pearsonmedia.loci.ui.screen.settings

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ExitToApp
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Fingerprint
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Group
import androidx.compose.material.icons.filled.GroupAdd
import androidx.compose.material.icons.filled.Security
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.Storage
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.pearsonmedia.loci.ui.theme.DesignTokens
import com.pearsonmedia.loci.ui.theme.LociGradients
import com.pearsonmedia.loci.ui.theme.premiumCard

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(
    onSignInClick: () -> Unit,
    onCreateHouseholdClick: () -> Unit = {},
    onJoinHouseholdClick: () -> Unit = {},
    onHouseholdMembersClick: () -> Unit = {},
    onUpgradeClick: () -> Unit = {}
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
    ) {
        TopAppBar(title = { Text("Settings") })

        // Premium account header card (US-173)
        AccountHeaderCard(
            displayName = "Guest",
            tierName = "Free",
            onUpgradeClick = onUpgradeClick
        )

        // Account Section
        SettingsSection(title = "Account") {
            SettingsItem(
                icon = Icons.Default.Person,
                title = "Sign In",
                subtitle = "Sync your loci across devices",
                onClick = onSignInClick
            )
        }

        // Subscription Section
        SettingsSection(title = "Subscription") {
            SettingsItem(
                icon = Icons.Default.Star,
                title = "Upgrade",
                subtitle = "Unlock Premium or Family features",
                onClick = onUpgradeClick
            )
        }

        // Family Section
        SettingsSection(title = "Family") {
            SettingsItem(
                icon = Icons.Default.Group,
                title = "Create Household",
                subtitle = "Start a family sharing group",
                onClick = onCreateHouseholdClick
            )
            HorizontalDivider()
            SettingsItem(
                icon = Icons.Default.GroupAdd,
                title = "Join Household",
                subtitle = "Enter an invite code",
                onClick = onJoinHouseholdClick
            )
            HorizontalDivider()
            SettingsItem(
                icon = Icons.Default.Person,
                title = "Household Members",
                subtitle = "Manage your family group",
                onClick = onHouseholdMembersClick
            )
        }

        // Notifications Section
        SettingsSection(title = "Notifications") {
            var notificationsEnabled by remember { mutableStateOf(true) }
            SettingsToggle(
                icon = Icons.Default.Notifications,
                title = "Proximity Alerts",
                subtitle = "Get notified near saved loci",
                checked = notificationsEnabled,
                onCheckedChange = { notificationsEnabled = it }
            )
        }

        // Security Section
        SettingsSection(title = "Security") {
            var biometricEnabled by remember { mutableStateOf(false) }
            SettingsToggle(
                icon = Icons.Default.Fingerprint,
                title = "Biometric Lock",
                subtitle = "Require fingerprint or face to open",
                checked = biometricEnabled,
                onCheckedChange = { biometricEnabled = it }
            )
        }

        // Data & Privacy Section
        SettingsSection(title = "Data & Privacy") {
            SettingsItem(
                icon = Icons.Default.Storage,
                title = "Data Management",
                subtitle = "Export or delete your data",
                onClick = { }
            )
        }

        // About Section
        SettingsSection(title = "About") {
            SettingsItem(
                icon = Icons.Default.Info,
                title = "About Loci",
                subtitle = "Version 1.0.0",
                onClick = { }
            )
        }

        Spacer(modifier = Modifier.height(32.dp))
    }
}

@Composable
private fun SettingsSection(
    title: String,
    content: @Composable () -> Unit
) {
    Column(modifier = Modifier.padding(vertical = 8.dp)) {
        Text(
            text = title,
            style = MaterialTheme.typography.labelLarge,
            color = MaterialTheme.colorScheme.primary,
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp)
        )
        Card(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp),
            elevation = CardDefaults.cardElevation(defaultElevation = 1.dp)
        ) {
            content()
        }
    }
}

@Composable
private fun SettingsItem(
    icon: ImageVector,
    title: String,
    subtitle: String,
    onClick: () -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(16.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Spacer(modifier = Modifier.width(16.dp))
        Column(modifier = Modifier.weight(1f)) {
            Text(text = title, style = MaterialTheme.typography.bodyLarge)
            Text(
                text = subtitle,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

@Composable
private fun SettingsToggle(
    icon: ImageVector,
    title: String,
    subtitle: String,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(16.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Spacer(modifier = Modifier.width(16.dp))
        Column(modifier = Modifier.weight(1f)) {
            Text(text = title, style = MaterialTheme.typography.bodyLarge)
            Text(
                text = subtitle,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
        Switch(checked = checked, onCheckedChange = onCheckedChange)
    }
}

/**
 * Premium account header (US-173).
 *
 * Gradient avatar tile with display initial, name, and a gradient tier
 * badge. Shown at the top of Settings above the first section.
 */
@Composable
private fun AccountHeaderCard(
    displayName: String,
    tierName: String,
    onUpgradeClick: () -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(
                horizontal = DesignTokens.Space.MD,
                vertical = DesignTokens.Space.SM
            )
            .premiumCard(
                radius = DesignTokens.Radius.LG,
                elevation = DesignTokens.Elevation.Level3,
                background = MaterialTheme.colorScheme.surface
            )
            .clickable(onClick = onUpgradeClick)
            .padding(DesignTokens.Space.MD),
        verticalAlignment = Alignment.CenterVertically
    ) {
        // Gradient avatar tile.
        Box(
            modifier = Modifier
                .size(56.dp)
                .clip(RoundedCornerShape(DesignTokens.Radius.MD))
                .background(LociGradients.Primary),
            contentAlignment = Alignment.Center
        ) {
            Text(
                text = displayName.take(1).uppercase(),
                style = MaterialTheme.typography.titleLarge,
                color = Color.White,
                fontWeight = FontWeight.Bold
            )
        }

        Spacer(modifier = Modifier.width(DesignTokens.Space.MD))

        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = displayName,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold
            )
            Spacer(modifier = Modifier.height(4.dp))
            // Gradient tier badge.
            Box(
                modifier = Modifier
                    .clip(CircleShape)
                    .background(
                        if (tierName.equals("Premium", ignoreCase = true)) LociGradients.Premium
                        else if (tierName.equals("Family", ignoreCase = true)) LociGradients.Family
                        else LociGradients.Primary
                    )
                    .padding(horizontal = 10.dp, vertical = 4.dp)
            ) {
                Text(
                    text = tierName,
                    style = MaterialTheme.typography.labelSmall,
                    color = Color.White,
                    fontWeight = FontWeight.SemiBold
                )
            }
        }
    }
}
