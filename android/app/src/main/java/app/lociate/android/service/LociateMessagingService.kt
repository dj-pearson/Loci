package app.lociate.android.service

import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import androidx.core.app.NotificationCompat
import app.lociate.android.LociateApplication
import app.lociate.android.R
import app.lociate.android.ui.MainActivity
import app.lociate.android.util.DeepLinkValidator
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import dagger.hilt.android.AndroidEntryPoint
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import timber.log.Timber
import javax.inject.Inject

/**
 * Receives Firebase Cloud Messaging payloads (US-197).
 *
 * Android had no push transport at all before this, so household-share
 * notifications and the weekly digest reached iOS devices only.
 */
@AndroidEntryPoint
class LociateMessagingService : FirebaseMessagingService() {

    @Inject
    lateinit var pushRegistrationService: PushRegistrationService

    // The service can be torn down mid-flight, so the token upsert runs on its own
    // supervisor scope rather than a lifecycle-bound one.
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    override fun onNewToken(token: String) {
        // FCM rotates tokens (app restore, data clear, reinstall). Without this the
        // server keeps a token that silently stops delivering.
        Timber.d("FCM token rotated")
        scope.launch { pushRegistrationService.onTokenReceived(token) }
    }

    override fun onMessageReceived(message: RemoteMessage) {
        // Data-only payloads let the client build the notification, so the channel,
        // deep link, and copy match the local geofence notifications exactly.
        val data = message.data
        val title = data["title"] ?: message.notification?.title ?: return
        val body = data["body"] ?: message.notification?.body ?: ""
        val locusId = data["locus_id"]

        sendNotification(title = title, body = body, locusId = locusId)
    }

    private fun sendNotification(title: String, body: String, locusId: String?) {
        // Validate before trusting: a push payload is remote input, and an
        // unvalidated id would flow straight into an Intent extra.
        val safeLocusId = locusId?.let { candidate ->
            val uri = android.net.Uri.parse("lociate://locus/$candidate")
            DeepLinkValidator.extractLocusIdFromUri(uri)
        }

        val intent = Intent(this, MainActivity::class.java).apply {
            action = Intent.ACTION_VIEW
            if (safeLocusId != null) putExtra("locus_id", safeLocusId)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }

        val pendingIntent = PendingIntent.getActivity(
            this,
            safeLocusId?.hashCode() ?: 0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(this, LociateApplication.CHANNEL_GEOFENCE)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .build()

        getSystemService(NotificationManager::class.java)
            .notify(safeLocusId?.hashCode() ?: NOTIFICATION_ID_DIGEST, notification)
    }

    companion object {
        /** Fixed id so successive digests replace rather than stack. */
        private const val NOTIFICATION_ID_DIGEST = 1
    }
}
