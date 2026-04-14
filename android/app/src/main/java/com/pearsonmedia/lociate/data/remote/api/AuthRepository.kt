package com.pearsonmedia.loci.data.remote.api

import com.pearsonmedia.loci.data.remote.SupabaseClientProvider
import com.pearsonmedia.loci.util.InputSanitizer
import com.pearsonmedia.loci.util.LoginAttemptTracker
import com.pearsonmedia.loci.util.SecurePreferences
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.auth.providers.builtin.Email
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import timber.log.Timber
import javax.inject.Inject
import javax.inject.Singleton

sealed class AuthState {
    data object Unauthenticated : AuthState()
    data object Loading : AuthState()
    data class Authenticated(val userId: String, val email: String) : AuthState()
    data class Error(val message: String) : AuthState()
}

@Singleton
class AuthRepository @Inject constructor(
    private val supabaseProvider: SupabaseClientProvider,
    private val securePreferences: SecurePreferences,
    private val loginAttemptTracker: LoginAttemptTracker
) {
    private val _authState = MutableStateFlow<AuthState>(AuthState.Unauthenticated)
    val authState: StateFlow<AuthState> = _authState.asStateFlow()

    private val auth get() = supabaseProvider.client.auth

    suspend fun signIn(email: String, password: String): Result<String> {
        val sanitizedEmail = InputSanitizer.sanitizeEmail(email)

        // Check lockout before attempting
        val lockout = loginAttemptTracker.checkLockout(sanitizedEmail)
        if (lockout.isLockedOut) {
            val minutes = (lockout.remainingSeconds + 59) / 60
            return Result.failure(
                Exception("Too many login attempts. Try again in $minutes minute(s).")
            )
        }

        _authState.value = AuthState.Loading

        return try {
            auth.signInWith(Email) {
                this.email = sanitizedEmail
                this.password = password
            }

            val session = auth.currentSessionOrNull()
            val userId = session?.user?.id ?: throw Exception("No session after sign in")

            // Store tokens securely
            securePreferences.putString(SecurePreferences.KEY_USER_ID, userId)
            securePreferences.putLong(
                SecurePreferences.KEY_LAST_ACTIVITY,
                System.currentTimeMillis()
            )

            loginAttemptTracker.recordSuccess(sanitizedEmail)
            _authState.value = AuthState.Authenticated(userId, sanitizedEmail)

            Timber.d("Sign in successful for user: $userId")
            Result.success(userId)
        } catch (e: Exception) {
            loginAttemptTracker.recordFailure(sanitizedEmail)
            // Generic error message to prevent email enumeration
            val message = "Invalid email or password"
            _authState.value = AuthState.Error(message)
            Timber.e(e, "Sign in failed")
            Result.failure(Exception(message))
        }
    }

    suspend fun signUp(email: String, password: String, displayName: String): Result<String> {
        val sanitizedEmail = InputSanitizer.sanitizeEmail(email)
        val sanitizedName = InputSanitizer.sanitize(displayName)

        _authState.value = AuthState.Loading

        return try {
            auth.signUpWith(Email) {
                this.email = sanitizedEmail
                this.password = password
                this.data = buildJsonObject {
                    put("display_name", sanitizedName)
                }
            }

            val session = auth.currentSessionOrNull()
            val userId = session?.user?.id ?: throw Exception("No session after sign up")

            securePreferences.putString(SecurePreferences.KEY_USER_ID, userId)
            _authState.value = AuthState.Authenticated(userId, sanitizedEmail)

            Timber.d("Sign up successful for user: $userId")
            Result.success(userId)
        } catch (e: Exception) {
            // Generic message to prevent email enumeration
            val message = "If this email is available, you will receive a confirmation."
            _authState.value = AuthState.Error(message)
            Timber.e(e, "Sign up failed")
            Result.failure(Exception(message))
        }
    }

    suspend fun signOut() {
        try {
            auth.signOut()
        } catch (e: Exception) {
            Timber.e(e, "Sign out API call failed")
        }

        securePreferences.remove(SecurePreferences.KEY_AUTH_TOKEN)
        securePreferences.remove(SecurePreferences.KEY_REFRESH_TOKEN)
        securePreferences.remove(SecurePreferences.KEY_USER_ID)
        securePreferences.remove(SecurePreferences.KEY_LAST_ACTIVITY)

        _authState.value = AuthState.Unauthenticated
        Timber.d("Signed out and cleared credentials")
    }

    suspend fun restoreSession(): Boolean {
        return try {
            val userId = securePreferences.getString(SecurePreferences.KEY_USER_ID)
            if (userId == null) {
                _authState.value = AuthState.Unauthenticated
                return false
            }

            // Check session expiry
            val lastActivity = securePreferences.getLong(SecurePreferences.KEY_LAST_ACTIVITY, 0)
            val expiryMs = com.pearsonmedia.loci.util.AppConstants.SESSION_EXPIRY_DAYS * 24 * 60 * 60 * 1000L
            if (System.currentTimeMillis() - lastActivity > expiryMs) {
                signOut()
                return false
            }

            auth.retrieveUser()
            val session = auth.currentSessionOrNull()
            if (session != null) {
                _authState.value = AuthState.Authenticated(
                    userId = session.user?.id ?: userId,
                    email = session.user?.email ?: ""
                )
                true
            } else {
                _authState.value = AuthState.Unauthenticated
                false
            }
        } catch (e: Exception) {
            Timber.e(e, "Session restore failed")
            _authState.value = AuthState.Unauthenticated
            false
        }
    }

    fun recordActivity() {
        securePreferences.putLong(
            SecurePreferences.KEY_LAST_ACTIVITY,
            System.currentTimeMillis()
        )
    }

    private fun buildJsonObject(block: JsonObjectBuilder.() -> Unit): kotlinx.serialization.json.JsonObject {
        return kotlinx.serialization.json.buildJsonObject(block)
    }
}

private typealias JsonObjectBuilder = kotlinx.serialization.json.JsonObjectBuilder

private fun JsonObjectBuilder.put(key: String, value: String) {
    this.put(key, kotlinx.serialization.json.JsonPrimitive(value))
}
