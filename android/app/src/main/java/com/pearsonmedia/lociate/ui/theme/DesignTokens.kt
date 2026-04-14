package com.pearsonmedia.loci.ui.theme

import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/**
 * Premium design tokens that layer on top of [LociTheme] to give the Loci
 * Android app a cohesive, high-end visual language. Keep the [MaterialTheme]
 * color scheme as the semantic source of truth; this file adds motion,
 * elevation, gradient, spacing, and radius primitives for the premium feel.
 */
object DesignTokens {

    // --- Spacing (8pt grid with half-steps) ---
    object Space {
        val Hairline: Dp = 2.dp
        val XXS: Dp = 4.dp
        val XS: Dp = 8.dp
        val SM: Dp = 12.dp
        val MD: Dp = 16.dp
        val LG: Dp = 20.dp
        val XL: Dp = 24.dp
        val XXL: Dp = 32.dp
        val XXXL: Dp = 48.dp
    }

    // --- Radius ---
    object Radius {
        val Pill: Dp = 6.dp
        val SM: Dp = 10.dp
        val MD: Dp = 14.dp
        val LG: Dp = 20.dp
        val XL: Dp = 28.dp
    }

    // --- Elevation ---
    object Elevation {
        val Level1: Dp = 2.dp
        val Level2: Dp = 6.dp
        val Level3: Dp = 12.dp
        val Level4: Dp = 20.dp
    }

    // --- Motion (spring specs) ---
    object Motion {
        /** Snappy — small controls, chips, toggles. */
        fun <T> snappy() = spring<T>(
            dampingRatio = 0.72f,
            stiffness = Spring.StiffnessMedium
        )

        /** Smooth — card reveals, sheet presentation. */
        fun <T> smooth() = spring<T>(
            dampingRatio = 0.82f,
            stiffness = Spring.StiffnessMediumLow
        )

        /** Gentle — hero transitions, onboarding pages. */
        fun <T> gentle() = spring<T>(
            dampingRatio = 0.88f,
            stiffness = Spring.StiffnessLow
        )

        /** Bouncy — celebratory feedback (save success, unlock). */
        fun <T> bouncy() = spring<T>(
            dampingRatio = 0.62f,
            stiffness = Spring.StiffnessMedium
        )

        /** Linear tween presets for value-driven animations. */
        fun <T> instant() = tween<T>(durationMillis = 120)
        fun <T> short() = tween<T>(durationMillis = 220)
        fun <T> medium() = tween<T>(durationMillis = 340)
        fun <T> long() = tween<T>(durationMillis = 550)
        fun <T> hero() = tween<T>(durationMillis = 800)

        const val StaggerMs: Long = 40L
    }
}

/**
 * Brand gradients. Use these for premium hero surfaces, paywall cards,
 * and the record button.
 */
object LociGradients {

    /** Primary diagonal — top-leading to bottom-trailing. */
    val Primary: Brush
        @Composable get() = Brush.linearGradient(
            colors = listOf(
                MaterialTheme.colorScheme.primary,
                MaterialTheme.colorScheme.secondary
            )
        )

    /** Record active — warm red/orange for the recording hero state. */
    val Record: Brush
        @Composable get() = Brush.verticalGradient(
            colors = listOf(
                MaterialTheme.colorScheme.error,
                LociOrange
            )
        )

    /** Premium tier showcase — indigo → blue → teal. */
    val Premium: Brush
        @Composable get() = Brush.linearGradient(
            colors = listOf(
                Color(0xFF5E5CE6),
                Color(0xFF0A84FF),
                Color(0xFF64D2FF)
            )
        )

    /** Family tier showcase — warm gold/pink for paywall. */
    val Family: Brush
        @Composable get() = Brush.linearGradient(
            colors = listOf(
                Color(0xFFFF9500),
                Color(0xFFFF375F)
            )
        )

    /** Soft primary halo — radial glow behind hero elements. */
    val PrimaryHalo: Brush
        @Composable get() = Brush.radialGradient(
            colors = listOf(
                MaterialTheme.colorScheme.primary.copy(alpha = 0.35f),
                MaterialTheme.colorScheme.primary.copy(alpha = 0f)
            ),
            radius = 600f
        )

    /** Glass surface tint — layered over translucent surfaces. */
    val GlassTint: Brush
        @Composable get() = Brush.verticalGradient(
            colors = listOf(
                Color.White.copy(alpha = 0.12f),
                Color.White.copy(alpha = 0.02f)
            )
        )
}

/**
 * Premium card modifier — rounded surface with elevation and optional
 * translucent border. Use for list cards, paywall tiers, and hero tiles.
 */
@Composable
fun Modifier.premiumCard(
    radius: Dp = DesignTokens.Radius.MD,
    elevation: Dp = DesignTokens.Elevation.Level2,
    background: Color = MaterialTheme.colorScheme.surface,
    border: BorderStroke? = null
): Modifier {
    val shape = RoundedCornerShape(radius)
    val base = this
        .shadow(elevation = elevation, shape = shape, clip = false)
        .clip(shape)
        .background(background, shape)
    return if (border != null) base.border(border, shape) else base
}
