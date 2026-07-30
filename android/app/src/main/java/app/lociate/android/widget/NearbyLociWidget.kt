package app.lociate.android.widget

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.GlanceTheme
import androidx.glance.LocalContext
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
// The Intent overload of actionStartActivity lives in the appwidget package, not
// androidx.glance.action — that one only offers the reified-Activity and
// ComponentName forms, neither of which can carry the lociate://locus/{id} deep link.
import androidx.glance.appwidget.action.actionStartActivity
import androidx.glance.appwidget.provideContent
import androidx.glance.background
import androidx.glance.layout.Alignment
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import app.lociate.android.R
import app.lociate.android.ui.MainActivity
import dagger.hilt.android.EntryPointAccessors
import timber.log.Timber

/**
 * Home-screen widget listing the nearest loci (US-213).
 *
 * The tier table advertises a widget on both platforms, but only iOS had one.
 * Content, ordering, and the three states (list / empty / Premium-locked) mirror
 * the iOS `NearbyLociTimelineProvider`.
 */
class NearbyLociWidget : GlanceAppWidget() {

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val snapshot = try {
            EntryPointAccessors
                .fromApplication(context, WidgetEntryPoint::class.java)
                .widgetDataSource()
                .load()
        } catch (e: Exception) {
            // A failed load must render an empty widget, never crash the launcher.
            // Defaulting to isPremium=true avoids falsely telling a paying user to
            // upgrade because the database was momentarily unreadable.
            Timber.e(e, "Widget data load failed")
            WidgetSnapshot(isPremium = true, loci = emptyList())
        }

        provideContent {
            GlanceTheme {
                when {
                    !snapshot.isPremium -> LockedState()
                    snapshot.loci.isEmpty() -> EmptyState()
                    else -> LociList(snapshot.loci)
                }
            }
        }
    }

    @Composable
    private fun LociList(loci: List<WidgetLocus>) {
        val context = LocalContext.current

        Column(
            modifier = GlanceModifier
                .fillMaxSize()
                .background(GlanceTheme.colors.widgetBackground)
                .padding(12.dp)
        ) {
            Text(
                text = context.getString(R.string.widget_title),
                style = TextStyle(
                    fontSize = 12.sp,
                    fontWeight = FontWeight.Bold,
                    color = GlanceTheme.colors.onSurface
                )
            )
            Spacer(GlanceModifier.height(6.dp))

            for (locus in loci) {
                Row(
                    modifier = GlanceModifier
                        .fillMaxWidth()
                        .padding(vertical = 3.dp)
                        .clickable(actionStartActivity(deepLinkIntent(context, locus.id))),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Column(modifier = GlanceModifier.defaultWeight()) {
                        Text(
                            text = locus.title,
                            maxLines = 1,
                            style = TextStyle(
                                fontSize = 12.sp,
                                fontWeight = FontWeight.Medium,
                                color = GlanceTheme.colors.onSurface
                            )
                        )
                        Text(
                            text = locus.transcription,
                            maxLines = 1,
                            style = TextStyle(
                                fontSize = 11.sp,
                                color = GlanceTheme.colors.onSurfaceVariant
                            )
                        )
                    }
                    Text(
                        text = locus.formattedDistance,
                        style = TextStyle(
                            fontSize = 11.sp,
                            color = GlanceTheme.colors.onSurfaceVariant
                        )
                    )
                }
            }
        }
    }

    /**
     * Opens the locus through the same `lociate://locus/<id>` route notifications
     * use, so `DeepLinkValidator` still vets the id — the widget is not a trusted
     * caller just because it ships in the same APK.
     */
    private fun deepLinkIntent(context: Context, locusId: String): Intent =
        Intent(context, MainActivity::class.java).apply {
            action = Intent.ACTION_VIEW
            data = Uri.parse("lociate://locus/$locusId")
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }

    @Composable
    private fun EmptyState() {
        CenteredMessage(
            title = LocalContext.current.getString(R.string.widget_empty),
            body = null
        )
    }

    @Composable
    private fun LockedState() {
        val context = LocalContext.current
        CenteredMessage(
            title = context.getString(R.string.widget_locked_title),
            body = context.getString(R.string.widget_locked_body),
            // Tapping the locked state should reach the paywall, not the map.
            onClickIntent = Intent(context, MainActivity::class.java).apply {
                action = Intent.ACTION_VIEW
                data = Uri.parse("lociate://paywall")
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
        )
    }

    @Composable
    private fun CenteredMessage(
        title: String,
        body: String?,
        onClickIntent: Intent? = null
    ) {
        var modifier = GlanceModifier
            .fillMaxSize()
            .background(GlanceTheme.colors.widgetBackground)
            .padding(12.dp)
        if (onClickIntent != null) {
            modifier = modifier.clickable(actionStartActivity(onClickIntent))
        }

        Column(
            modifier = modifier,
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = title,
                style = TextStyle(
                    fontSize = 13.sp,
                    fontWeight = FontWeight.Bold,
                    color = GlanceTheme.colors.onSurface
                )
            )
            if (body != null) {
                Spacer(GlanceModifier.height(4.dp))
                Text(
                    text = body,
                    style = TextStyle(
                        fontSize = 11.sp,
                        color = GlanceTheme.colors.onSurfaceVariant
                    )
                )
            }
        }
    }
}

/** Registered in AndroidManifest.xml against nearby_loci_widget_info.xml. */
class NearbyLociWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = NearbyLociWidget()
}
