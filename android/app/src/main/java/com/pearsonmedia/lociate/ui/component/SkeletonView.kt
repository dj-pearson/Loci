package com.pearsonmedia.lociate.ui.component

import android.animation.ValueAnimator
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/**
 * Shimmering skeleton placeholder (US-171).
 *
 * Uses a sweeping LinearGradient brush translated across the box via an
 * infinite transition. If the system has animators disabled (accessibility
 * Reduce Motion), the sweep collapses to a static translucent fill.
 */
@Composable
fun SkeletonBox(
    width: Dp = Dp.Unspecified,
    height: Dp = 16.dp,
    modifier: Modifier = Modifier
) {
    val animatorsEnabled = remember { ValueAnimator.areAnimatorsEnabled() }

    val base = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.10f)
    val highlight = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.22f)

    val brush: Brush = if (animatorsEnabled) {
        val transition = rememberInfiniteTransition(label = "shimmer")
        val translateX by transition.animateFloat(
            initialValue = -400f,
            targetValue = 800f,
            animationSpec = infiniteRepeatable(
                animation = tween(durationMillis = 1400, easing = LinearEasing),
                repeatMode = RepeatMode.Restart
            ),
            label = "shimmer_x"
        )
        Brush.linearGradient(
            colors = listOf(base, highlight, base),
            start = Offset(translateX, 0f),
            end = Offset(translateX + 300f, 0f)
        )
    } else {
        Brush.linearGradient(colors = listOf(base, base))
    }

    Box(
        modifier = modifier
            .then(if (width != Dp.Unspecified) Modifier.width(width) else Modifier.fillMaxWidth())
            .height(height)
            .clip(RoundedCornerShape(4.dp))
            .background(brush)
    )
}

@Composable
fun SkeletonLocusListItem(modifier: Modifier = Modifier) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .padding(16.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        SkeletonBox(
            width = 44.dp,
            height = 44.dp,
            modifier = Modifier.clip(RoundedCornerShape(10.dp))
        )

        Spacer(modifier = Modifier.width(12.dp))

        Column(modifier = Modifier.weight(1f)) {
            SkeletonBox(width = 180.dp, height = 16.dp)
            Spacer(modifier = Modifier.height(8.dp))
            SkeletonBox(height = 12.dp)
            Spacer(modifier = Modifier.height(4.dp))
            SkeletonBox(width = 100.dp, height = 10.dp)
        }
    }
}

@Composable
fun SkeletonLocusList(count: Int = 5) {
    Column {
        repeat(count) {
            SkeletonLocusListItem()
        }
    }
}
