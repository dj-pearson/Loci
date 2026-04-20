package app.lociate.android.ui.theme

import android.os.Build
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext

// Lociate Brand Colors
val LociateBlue = Color(0xFF4A90D9)
val LociateBlueLight = Color(0xFF7BB3E8)
val LociateBlueDark = Color(0xFF2D6CB5)
val LociateOrange = Color(0xFFFF8A50)
val LociateGreen = Color(0xFF66BB6A)
val LociateRed = Color(0xFFEF5350)
val LociateSurface = Color(0xFFFAFAFA)
val LociateSurfaceDark = Color(0xFF1C1C1E)
val LociateBackground = Color(0xFFFFFFFF)
val LociateBackgroundDark = Color(0xFF000000)

private val LightColorScheme = lightColorScheme(
    primary = LociateBlue,
    onPrimary = Color.White,
    primaryContainer = LociateBlueLight,
    onPrimaryContainer = LociateBlueDark,
    secondary = LociateOrange,
    onSecondary = Color.White,
    tertiary = LociateGreen,
    background = LociateBackground,
    surface = LociateSurface,
    error = LociateRed,
    onBackground = Color(0xFF1C1C1E),
    onSurface = Color(0xFF1C1C1E),
    outline = Color(0xFFD1D1D6)
)

private val DarkColorScheme = darkColorScheme(
    primary = LociateBlueLight,
    onPrimary = Color(0xFF003258),
    primaryContainer = LociateBlueDark,
    onPrimaryContainer = Color(0xFFD1E4FF),
    secondary = LociateOrange,
    onSecondary = Color(0xFF4E2600),
    tertiary = LociateGreen,
    background = LociateBackgroundDark,
    surface = LociateSurfaceDark,
    error = Color(0xFFFFB4AB),
    onBackground = Color(0xFFE6E1E5),
    onSurface = Color(0xFFE6E1E5),
    outline = Color(0xFF48484A)
)

@Composable
fun LociateTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    dynamicColor: Boolean = true,
    content: @Composable () -> Unit
) {
    val colorScheme = when {
        dynamicColor && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S -> {
            val context = LocalContext.current
            if (darkTheme) dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)
        }
        darkTheme -> DarkColorScheme
        else -> LightColorScheme
    }

    MaterialTheme(
        colorScheme = colorScheme,
        typography = LociateTypography,
        content = content
    )
}
