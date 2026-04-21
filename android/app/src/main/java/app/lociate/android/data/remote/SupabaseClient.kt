package app.lociate.android.data.remote

import app.lociate.android.BuildConfig
import app.lociate.android.util.CertificatePinning
import app.lociate.android.util.RequestSigningInterceptor
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.Auth
import io.github.jan.supabase.createSupabaseClient
import io.github.jan.supabase.postgrest.Postgrest
import io.github.jan.supabase.storage.Storage
import io.ktor.client.engine.okhttp.OkHttp
import okhttp3.OkHttpClient
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Supabase client singleton configured for the Lociate backend.
 * Shares the same PostgreSQL/PostGIS backend as the iOS app.
 *
 * The underlying Ktor engine is OkHttp so we can install:
 * - `CertificatePinner` — pins Supabase TLS certificates (no-op if pins unset)
 * - `RequestSigningInterceptor` — HMAC-signs outbound requests (no-op if key unset)
 * Both read their config from BuildConfig; empty values gracefully disable
 * the feature for local development.
 */
@Singleton
class SupabaseClientProvider @Inject constructor() {

    val client: SupabaseClient by lazy {
        createSupabaseClient(
            supabaseUrl = BuildConfig.SUPABASE_URL,
            supabaseKey = BuildConfig.SUPABASE_ANON_KEY,
        ) {
            httpEngine = OkHttp.create {
                preconfigured = OkHttpClient.Builder()
                    .certificatePinner(CertificatePinning.createCertificatePinner())
                    .addInterceptor(RequestSigningInterceptor())
                    .build()
            }
            install(Auth) {
                // Session auto-refresh is handled by the SDK
            }
            install(Postgrest)
            install(Storage)
        }
    }
}
