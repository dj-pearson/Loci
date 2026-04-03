package com.pearsonmedia.loci.util

object AppConstants {
    // Tier limits
    const val MAX_FREE_LOCI = 10
    const val MAX_HOUSEHOLD_MEMBERS = 6

    // Geofencing
    const val MAX_GEOFENCES = 100 // Android limit (vs iOS 20)
    const val GEOFENCE_RADIUS_METERS = 100f

    // Audio format
    const val AUDIO_SAMPLE_RATE = 44100
    const val AUDIO_BIT_RATE = 64000 // 64kbps mono M4A/AAC
    const val AUDIO_CHANNELS = 1

    // Household
    const val INVITE_CODE_LENGTH = 6
    const val INVITE_EXPIRY_HOURS = 48

    // Session
    const val SESSION_EXPIRY_DAYS = 30
    const val SESSION_ACTIVITY_THROTTLE_MINUTES = 5
    const val TOKEN_REFRESH_MAX_RETRIES = 3

    // Auth
    const val MAX_LOGIN_ATTEMPTS_BEFORE_LOCKOUT = 10
    const val LOGIN_LOCKOUT_DURATION_MINUTES = 60

    // Network
    const val CONNECT_TIMEOUT_SECONDS = 30L
    const val READ_TIMEOUT_SECONDS = 60L
    const val MAX_RETRY_ATTEMPTS = 3

    // Notification channels
    const val CHANNEL_GEOFENCE = "geofence_notifications"
    const val CHANNEL_SYNC = "sync_notifications"
    const val CHANNEL_RECORDING = "recording_notifications"
}
