package com.pearsonmedia.lociate.data.remote

import com.pearsonmedia.lociate.BuildConfig
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.Auth
import io.github.jan.supabase.createSupabaseClient
import io.github.jan.supabase.postgrest.Postgrest
import io.github.jan.supabase.storage.Storage
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Supabase client singleton configured for the Lociate backend.
 * Shares the same PostgreSQL/PostGIS backend as the iOS app.
 */
@Singleton
class SupabaseClientProvider @Inject constructor() {

    val client: SupabaseClient by lazy {
        createSupabaseClient(
            supabaseUrl = BuildConfig.SUPABASE_URL,
            supabaseKey = BuildConfig.SUPABASE_ANON_KEY
        ) {
            install(Auth) {
                // Session auto-refresh is handled by the SDK
            }
            install(Postgrest)
            install(Storage)
        }
    }
}
