package com.pearsonmedia.lociate.domain.model

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Dining
import androidx.compose.material.icons.filled.DirectionsCar
import androidx.compose.material.icons.filled.Explore
import androidx.compose.material.icons.filled.FitnessCenter
import androidx.compose.material.icons.filled.Forest
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Lightbulb
import androidx.compose.material.icons.filled.LocationOn
import androidx.compose.material.icons.filled.ShoppingCart
import androidx.compose.material.icons.filled.Warning
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector

enum class LocusCategory(
    val displayName: String,
    val icon: ImageVector,
    val color: Color
) {
    GENERAL("General", Icons.Default.LocationOn, Color(0xFF5C6BC0)),
    FOOD("Food", Icons.Default.Dining, Color(0xFFEF5350)),
    SHOPPING("Shopping", Icons.Default.ShoppingCart, Color(0xFFAB47BC)),
    PARKING("Parking", Icons.Default.DirectionsCar, Color(0xFF42A5F5)),
    HEALTH("Health", Icons.Default.FitnessCenter, Color(0xFF66BB6A)),
    TRAVEL("Travel", Icons.Default.Explore, Color(0xFFFFA726)),
    TIP("Tip", Icons.Default.Lightbulb, Color(0xFFFFEE58)),
    WARNING("Warning", Icons.Default.Warning, Color(0xFFFF7043)),
    HOME("Home", Icons.Default.Home, Color(0xFF8D6E63)),
    OUTDOOR("Outdoor", Icons.Default.Forest, Color(0xFF26A69A));

    companion object {
        fun fromString(value: String): LocusCategory {
            return entries.find { it.name.equals(value, ignoreCase = true) } ?: GENERAL
        }
    }
}
