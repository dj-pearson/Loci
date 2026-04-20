package app.lociate.android.ui.component

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.LocationOff
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import app.lociate.android.ui.theme.DesignTokens
import app.lociate.android.ui.theme.LociateGradients

/**
 * Premium empty state (US-171).
 *
 * Hero icon sitting on a gradient halo backdrop, headline, supporting
 * copy. Used on empty map, empty list, empty search.
 */
@Composable
fun EmptyStateView(
    title: String,
    description: String,
    modifier: Modifier = Modifier,
    icon: ImageVector = Icons.Default.LocationOff
) {
    Column(
        modifier = modifier.padding(DesignTokens.Space.XL),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        // Hero icon on a gradient halo.
        Box(
            modifier = Modifier.size(220.dp),
            contentAlignment = Alignment.Center
        ) {
            Box(
                modifier = Modifier
                    .size(220.dp)
                    .clip(CircleShape)
                    .background(LociateGradients.PrimaryHalo)
            )
            Box(
                modifier = Modifier
                    .size(96.dp)
                    .clip(CircleShape)
                    .background(LociateGradients.Primary),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    imageVector = icon,
                    contentDescription = null,
                    modifier = Modifier.size(44.dp),
                    tint = Color.White
                )
            }
        }

        Spacer(modifier = Modifier.height(DesignTokens.Space.MD))

        Text(
            text = title,
            style = MaterialTheme.typography.titleLarge,
            textAlign = TextAlign.Center
        )

        Spacer(modifier = Modifier.height(DesignTokens.Space.XS))

        Text(
            text = description,
            style = MaterialTheme.typography.bodyMedium,
            textAlign = TextAlign.Center,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}
