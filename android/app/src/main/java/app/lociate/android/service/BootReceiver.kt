package app.lociate.android.service

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import timber.log.Timber

/**
 * Re-registers geofences after a reboot (US-219).
 *
 * Android drops every registered geofence on reboot, so without this the app's
 * proximity notifications stay dead until something else re-registers them. The
 * previous implementation only logged "geofences will be re-registered on next app
 * launch" — and nothing on app launch registered them either, so the core feature
 * never worked at all.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return

        Timber.d("Boot completed — enqueueing geofence re-registration")
        // WorkManager rather than direct registration: a BroadcastReceiver has
        // roughly ten seconds and cannot safely do database I/O, and the work must
        // survive the receiver being torn down.
        GeofenceRegistrationWorker.enqueue(context)
    }
}
