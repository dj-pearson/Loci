package app.lociate.android.ui.component

import androidx.compose.foundation.Canvas
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.StrokeCap

@Composable
fun AudioWaveform(
    amplitude: Float,
    modifier: Modifier = Modifier
) {
    val color = MaterialTheme.colorScheme.primary
    val barCount = 40
    val amplitudes = remember { FloatArray(barCount) }

    // Shift amplitudes left and add new value
    for (i in 0 until barCount - 1) {
        amplitudes[i] = amplitudes[i + 1]
    }
    amplitudes[barCount - 1] = amplitude

    Canvas(modifier = modifier) {
        val barWidth = size.width / barCount
        val maxHeight = size.height

        amplitudes.forEachIndexed { index, amp ->
            val barHeight = (amp * maxHeight).coerceAtLeast(4f)
            val x = index * barWidth + barWidth / 2
            val yCenter = size.height / 2

            drawLine(
                color = color.copy(alpha = 0.4f + (amp * 0.6f)),
                start = Offset(x, yCenter - barHeight / 2),
                end = Offset(x, yCenter + barHeight / 2),
                strokeWidth = barWidth * 0.6f,
                cap = StrokeCap.Round
            )
        }
    }
}
