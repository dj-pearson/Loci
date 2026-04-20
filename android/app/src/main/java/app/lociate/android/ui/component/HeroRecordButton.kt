package com.pearsonmedia.lociate.ui.component

import android.animation.ValueAnimator
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.LinearOutSlowInEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.FloatingActionButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.pearsonmedia.lociate.ui.theme.DesignTokens
import com.pearsonmedia.lociate.ui.theme.LociateGradients

/**
 * Premium hero record button (US-166).
 *
 * Mirrors the iOS RecordButton treatment:
 *  - Idle: gradient fill with a breathing primary halo driven by an
 *    infinite transition + gentle spring motion.
 *  - Active: warm record gradient and an amplitude-driven stroke ring
 *    that pulses with the incoming audio.
 *  - Press: snappy scale feedback.
 *  - Reduce-motion friendly: callers can pass `animate = false` to
 *    collapse all infinite animations into static states.
 */
@Composable
fun HeroRecordButton(
    isRecording: Boolean,
    amplitude: Float,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    animate: Boolean = ValueAnimator.areAnimatorsEnabled()
) {
    val interactionSource = remember { MutableInteractionSource() }
    val isPressed by interactionSource.collectIsPressedAsState()

    val pressScale by animateFloatAsState(
        targetValue = if (isPressed) 0.92f else 1f,
        animationSpec = DesignTokens.Motion.snappy(),
        label = "pressScale"
    )

    // Breathing halo for idle state.
    val transition = rememberInfiniteTransition(label = "record_halo")
    val haloScale by transition.animateFloat(
        initialValue = 0.96f,
        targetValue = if (animate && !isRecording) 1.08f else 0.96f,
        animationSpec = infiniteRepeatable(
            animation = tween(1600, easing = LinearOutSlowInEasing),
            repeatMode = RepeatMode.Reverse
        ),
        label = "haloScale"
    )
    val haloAlpha by transition.animateFloat(
        initialValue = 0.55f,
        targetValue = if (animate && !isRecording) 0.25f else 0.55f,
        animationSpec = infiniteRepeatable(
            animation = tween(1600, easing = LinearOutSlowInEasing),
            repeatMode = RepeatMode.Reverse
        ),
        label = "haloAlpha"
    )

    val clampedAmplitude = amplitude.coerceIn(0f, 1f)
    val ringExpand by animateFloatAsState(
        targetValue = if (isRecording) 1f + clampedAmplitude * 0.22f else 1f,
        animationSpec = tween(80),
        label = "ringExpand"
    )

    val iconColor by animateColorAsState(
        targetValue = Color.White,
        label = "iconColor"
    )

    val idleBrush: Brush = LociateGradients.Primary
    val recordBrush: Brush = LociateGradients.Record
    val haloBrush: Brush = LociateGradients.PrimaryHalo

    val sizeDp = 88.dp

    Box(
        modifier = modifier
            .size(sizeDp + 120.dp)
            .semantics {
                role = Role.Button
                contentDescription = if (isRecording) "Stop recording" else "Record voice note"
            },
        contentAlignment = Alignment.Center
    ) {
        // Idle breathing halo — suppressed during recording.
        if (!isRecording) {
            Box(
                modifier = Modifier
                    .size(sizeDp + 120.dp)
                    .scale(haloScale)
                    .drawBehind {
                        drawCircle(
                            brush = haloBrush,
                            alpha = haloAlpha
                        )
                    }
            )
        }

        // Active amplitude ring — only when recording.
        if (isRecording) {
            Canvas(
                modifier = Modifier
                    .size(sizeDp + 36.dp)
                    .scale(ringExpand)
            ) {
                drawCircle(
                    brush = recordBrush,
                    radius = size.minDimension / 2f,
                    style = Stroke(width = 4.dp.toPx()),
                    alpha = 0.85f
                )
            }
        }

        // Main button.
        FloatingActionButton(
            onClick = onClick,
            interactionSource = interactionSource,
            shape = CircleShape,
            containerColor = Color.Transparent,
            contentColor = Color.White,
            elevation = FloatingActionButtonDefaults.elevation(
                defaultElevation = DesignTokens.Elevation.Level3,
                pressedElevation = DesignTokens.Elevation.Level2
            ),
            modifier = Modifier
                .size(sizeDp)
                .scale(pressScale)
                .clip(CircleShape)
                .drawBehind {
                    drawCircle(brush = if (isRecording) recordBrush else idleBrush)
                }
        ) {
            Icon(
                imageVector = if (isRecording) Icons.Default.Stop else Icons.Default.Mic,
                contentDescription = null,
                modifier = Modifier.size(36.dp),
                tint = iconColor
            )
        }
    }
}
