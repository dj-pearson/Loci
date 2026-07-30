package app.lociate.android.service

import app.lociate.android.data.remote.SupabaseClientProvider
import app.lociate.android.util.SecurePreferences
import com.google.firebase.messaging.FirebaseMessaging
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.postgrest.postgrest
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonPrimitive
import timber.log.Timber
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Obtains the FCM registration token and keeps `users.fcm_token` in sync (US-197).
 *
 * Mirrors the iOS `PushRegistrationService`: a token obtained while offline or
 * signed out is queued locally and flushed on the next sign-in or connectivity
 * change, and sign-out clears the column server-side so a shared device stops
 * receiving the previous account's notifications.
 */
@Singleton
class PushRegistrationService @Inject constructor(
    private val supabaseProvider: SupabaseClientProvider,
    private val securePreferences: SecurePreferences
) {
    private val postgrest get() = supabaseProvider.client.postgrest
    private val auth get() = supabaseProvider.client.auth

    /**
     * Requests a token from FCM.
     *
     * Returns without error when Firebase is not configured: a self-hosted build
     * with no google-services.json should still run, just without remote push.
     */
    suspend fun registerForPush() = withContext(Dispatchers.IO) {
        val token = try {
            FirebaseMessaging.getInstance().token.await()
        } catch (e: Exception) {
            // Missing google-services.json, no Play Services, or a network failure.
            // Local geofence notifications are unaffected, so this is not fatal.
            Timber.w(e, "FCM token unavailable — remote push disabled for this session")
            return@withContext
        }

        onTokenReceived(token)
    }

    /** Called from [LociateMessagingService.onNewToken] and after [registerForPush]. */
    suspend fun onTokenReceived(token: String) {
        if (token == securePreferences.getString(KEY_SYNCED_TOKEN)) {
            Timber.d("FCM token unchanged — nothing to upsert")
            return
        }
        securePreferences.putString(KEY_PENDING_TOKEN, token)
        syncPendingToken()
    }

    /**
     * Flushes a queued token. Safe to call repeatedly — no-ops when there is
     * nothing pending or no session.
     */
    suspend fun syncPendingToken() = withContext(Dispatchers.IO) {
        val token = securePreferences.getString(KEY_PENDING_TOKEN) ?: return@withContext
        val authId = auth.currentSessionOrNull()?.user?.id
        if (authId == null) {
            // Signed out: keep it queued for after the next sign-in rather than
            // discarding a token FCM will not hand out again.
            Timber.d("No session — leaving FCM token queued")
            return@withContext
        }

        try {
            postgrest.from("users")
                .update(JsonObject(mapOf("fcm_token" to JsonPrimitive(token)))) {
                    filter { eq("auth_id", authId) }
                }
            securePreferences.putString(KEY_SYNCED_TOKEN, token)
            securePreferences.remove(KEY_PENDING_TOKEN)
            Timber.d("FCM token registered for the current user")
        } catch (e: Exception) {
            // Stays pending; retried on the next sign-in, connectivity change, or
            // app start.
            Timber.e(e, "Failed to upsert FCM token")
        }
    }

    /** Re-binds the current token after a sign-in, since it now belongs to a new account. */
    suspend fun onSignIn() {
        val token = securePreferences.getString(KEY_SYNCED_TOKEN)
            ?: securePreferences.getString(KEY_PENDING_TOKEN)
        if (token != null) {
            securePreferences.putString(KEY_PENDING_TOKEN, token)
            securePreferences.remove(KEY_SYNCED_TOKEN)
        }
        syncPendingToken()
    }

    /**
     * Clears the column server-side, then locally.
     *
     * Order matters: after the session is gone there is no authenticated row to
     * update, and a stale token keeps delivering the previous account's digests to
     * this device.
     */
    suspend fun onSignOut() = withContext(Dispatchers.IO) {
        val authId = auth.currentSessionOrNull()?.user?.id
        if (authId != null) {
            try {
                postgrest.from("users")
                    .update(JsonObject(mapOf("fcm_token" to JsonNull))) {
                        filter { eq("auth_id", authId) }
                    }
                Timber.d("FCM token cleared for the signed-out user")
            } catch (e: Exception) {
                Timber.e(e, "Failed to clear FCM token")
            }
        }
        securePreferences.remove(KEY_SYNCED_TOKEN)
        securePreferences.remove(KEY_PENDING_TOKEN)
    }

    /** After account deletion the row is already gone; drop local state only. */
    fun onAccountDeleted() {
        securePreferences.remove(KEY_SYNCED_TOKEN)
        securePreferences.remove(KEY_PENDING_TOKEN)
    }

    companion object {
        const val KEY_SYNCED_TOKEN = "push_synced_fcm_token"
        const val KEY_PENDING_TOKEN = "push_pending_fcm_token"
    }
}
