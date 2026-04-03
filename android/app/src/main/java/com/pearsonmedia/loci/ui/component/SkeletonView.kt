package com.pearsonmedia.loci.ui.component

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
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

@Composable
fun SkeletonBox(
    width: Dp = Dp.Unspecified,
    height: Dp = 16.dp,
    modifier: Modifier = Modifier
) {
    val infiniteTransition = rememberInfiniteTransition(label = "shimmer")
    val alpha by infiniteTransition.animateFloat(
        initialValue = 0.3f,
        targetValue = 0.7f,
        animationSpec = infiniteRepeatable(
            animation = tween(1000),
            repeatMode = RepeatMode.Reverse
        ),
        label = "shimmer_alpha"
    )

    Box(
        modifier = modifier
            .then(if (width != Dp.Unspecified) Modifier.width(width) else Modifier.fillMaxWidth())
            .height(height)
            .clip(RoundedCornerShape(4.dp))
            .graphicsLayer { this.alpha = alpha }
            .background(MaterialTheme.colorScheme.onSurface.copy(alpha = 0.12f))
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
            width = 40.dp,
            height = 40.dp,
            modifier = Modifier.clip(CircleShape)
        )

        Spacer(modifier = Modifier.width(12.dp))

        Column(modifier = Modifier.weight(1f)) {
            SkeletonBox(width = 160.dp, height = 16.dp)
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
