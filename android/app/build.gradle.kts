import java.util.Properties

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.hilt.android)
    alias(libs.plugins.ksp)
    alias(libs.plugins.kotlin.serialization)
}

// Gradle auto-loads `gradle.properties`, but NOT `local.properties` — that file is
// only special to the Android SDK locator (`sdk.dir`). Every `findProperty` below
// therefore returned null no matter what `scripts/generate-secrets.sh --android`
// wrote, so the build silently used placeholder credentials and the release Maps-key
// guard could never be satisfied. Loading it explicitly is what makes the generated
// file actually reach the build.
val localProperties = Properties().apply {
    val file = rootProject.file("local.properties")
    if (file.exists()) {
        file.inputStream().use { load(it) }
    }
}

/**
 * Resolves a build secret: `local.properties` first, then `-P`/`gradle.properties`,
 * then the environment (which is how CI passes them without writing a file).
 */
fun secret(name: String, default: String = ""): String =
    localProperties.getProperty(name)
        ?: project.findProperty(name) as String?
        ?: System.getenv(name)
        ?: default

// US-197: the Google Services plugin hard-fails when google-services.json is
// missing, and that file is gitignored. Applying it conditionally keeps the build
// working for a contributor without Firebase credentials — FCM then degrades to a
// logged no-op at runtime (see PushRegistrationService.registerForPush).
val googleServicesJson = file("google-services.json")
if (googleServicesJson.exists()) {
    apply(plugin = "com.google.gms.google-services")
} else {
    logger.lifecycle(
        "google-services.json not found — Firebase Cloud Messaging is disabled in " +
            "this build. See android/google-services.json.example."
    )
}

android {
    namespace = "app.lociate.android"
    compileSdk = 35

    defaultConfig {
        applicationId = "app.lociate.android"
        minSdk = 26
        targetSdk = 35
        versionCode = 1
        versionName = "1.0.0"

        testInstrumentationRunner = "app.lociate.android.HiltTestRunner"

        // Configuration — replace with actual values in local.properties (see
        // local.properties.example) or via scripts/generate-secrets.sh --android.
        buildConfigField("String", "SUPABASE_URL", "\"${secret("SUPABASE_URL", "https://your-supabase-url.com")}\"")
        buildConfigField("String", "SUPABASE_ANON_KEY", "\"${secret("SUPABASE_ANON_KEY", "your-anon-key")}\"")
        buildConfigField("String", "MAPS_API_KEY", "\"${secret("MAPS_API_KEY")}\"")
        // US-190: AndroidManifest.xml substitutes ${MAPS_API_KEY} into the
        // com.google.android.geo.API_KEY meta-data. Without this placeholder the
        // manifest merger fails and no variant can be assembled — the buildConfigField
        // above is only readable at runtime, it does not feed the manifest.
        manifestPlaceholders["MAPS_API_KEY"] = secret("MAPS_API_KEY")
        // Certificate pinning (SPKI SHA-256 hashes, base64). Empty values disable pinning.
        buildConfigField("String", "CERT_PIN_HASH", "\"${secret("CERT_PIN_HASH")}\"")
        buildConfigField("String", "CERT_BACKUP_PIN_HASH", "\"${secret("CERT_BACKUP_PIN_HASH")}\"")
        // HMAC-SHA256 shared secret for signing sensitive API mutations. Must match
        // REQUEST_SIGNING_KEY on the edge function server. Empty disables signing.
        buildConfigField("String", "REQUEST_SIGNING_KEY", "\"${secret("REQUEST_SIGNING_KEY")}\"")
        // US-197: lets runtime code skip FCM work entirely rather than relying on a
        // caught exception when Firebase was never configured.
        buildConfigField("Boolean", "FCM_ENABLED", googleServicesJson.exists().toString())
        // US-199: crash reporting. An empty DSN disables Sentry cleanly.
        buildConfigField("String", "SENTRY_DSN", "\"${secret("SENTRY_DSN")}\"")

        javaCompileOptions {
            annotationProcessorOptions {
                arguments += mapOf(
                    "room.schemaLocation" to "$projectDir/schemas",
                    "room.incremental" to "true"
                )
            }
        }
    }

    buildTypes {
        release {
            // The Maps key guard is NOT here — it is attached to the release tasks
            // further down this file. A `release { }` block is evaluated on every
            // Gradle invocation, so throwing from it broke `lintDebug` and
            // `assembleDebug` as well.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
        debug {
            isDebuggable = true
            applicationIdSuffix = ".debug"
            if (secret("MAPS_API_KEY").isBlank()) {
                logger.warn(
                    "MAPS_API_KEY is not set — the map screen will render blank in this " +
                        "debug build. See android/local.properties.example."
                )
            }
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }

    testOptions {
        unitTests.isIncludeAndroidResources = true
    }

    // US-208: MigrationTestHelper reads the exported schema JSON from the assets of
    // the androidTest APK, so the schemas directory has to be on that source set.
    sourceSets {
        getByName("androidTest") {
            assets.srcDirs("$projectDir/schemas")
        }
    }

    packaging {
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
        }
    }

    ksp {
        arg("room.schemaLocation", "$projectDir/schemas")
    }
}

// US-190: a release build with no Maps key ships an app whose map screen is
// permanently blank, so it must fail. The check has to be attached to the release
// tasks rather than written inside `buildTypes { release { } }`: that block is
// evaluated during configuration on *every* invocation, so the throw fired for
// `lintDebug` and `assembleDebug` too and took the whole Android CI job down with it.
//
// Reading the properties out here, into plain values, keeps the task action free of
// any reference to `project` — a requirement for the configuration cache.
val mapsKeyForReleaseGuard = secret("MAPS_API_KEY")
val mapsKeyGuardBypassed = project.hasProperty("allowMissingMapsKey")

// `preReleaseBuild` runs before anything else in a release build, so this fails fast
// rather than after a full minified package has been produced. The two lifecycle
// tasks are belt-and-braces in case a future AGP renames it.
tasks.matching {
    it.name in setOf("preReleaseBuild", "assembleRelease", "bundleRelease")
}.configureEach {
    doFirst {
        if (mapsKeyForReleaseGuard.isBlank() && !mapsKeyGuardBypassed) {
            throw GradleException(
                "MAPS_API_KEY is not set. Add it to android/local.properties (see " +
                    "local.properties.example) or run scripts/generate-secrets.sh --android. " +
                    "Pass -PallowMissingMapsKey to bypass for a non-shippable build."
            )
        }
    }
}

dependencies {
    // Compose BOM
    val composeBom = platform(libs.compose.bom)
    implementation(composeBom)
    androidTestImplementation(composeBom)

    implementation(libs.compose.ui)
    implementation(libs.compose.ui.graphics)
    implementation(libs.compose.ui.tooling.preview)
    implementation(libs.compose.material3)
    implementation(libs.compose.material.icons)
    implementation(libs.compose.animation)
    debugImplementation(libs.compose.ui.tooling)
    debugImplementation(libs.compose.ui.test.manifest)

    // Lifecycle
    implementation(libs.lifecycle.runtime)
    implementation(libs.lifecycle.viewmodel)

    // Navigation
    implementation(libs.navigation.compose)

    // Hilt DI
    implementation(libs.hilt.android)
    ksp(libs.hilt.compiler)
    implementation(libs.hilt.navigation)

    // Room Database
    implementation(libs.room.runtime)
    implementation(libs.room.ktx)
    ksp(libs.room.compiler)

    // DataStore & Security
    implementation(libs.datastore)
    implementation(libs.security.crypto)
    implementation(libs.biometric)
    // US-212: BiometricPrompt needs a FragmentActivity host, so MainActivity
    // extends FragmentActivity rather than ComponentActivity.
    implementation(libs.fragment.ktx)

    // Location
    implementation(libs.play.services.location)

    // Maps
    implementation(libs.maps.compose)
    implementation(libs.play.services.maps)

    // Audio/Media
    implementation(libs.media3.exoplayer)
    implementation(libs.media3.ui)

    // Supabase
    implementation(libs.supabase.auth)
    implementation(libs.supabase.postgrest)
    implementation(libs.supabase.storage)
    implementation(libs.supabase.realtime)

    // Ktor (OkHttp engine lets SupabaseClient install cert pinner + signing interceptor)
    implementation(libs.ktor.okhttp)
    implementation(libs.ktor.content.negotiation)
    implementation(libs.ktor.serialization)

    // OkHttp (used by CertificatePinning + RequestSigningInterceptor)
    implementation(libs.okhttp)

    // Serialization
    implementation(libs.serialization.json)

    // Coroutines
    implementation(libs.coroutines.android)
    implementation(libs.coroutines.play.services)

    // WorkManager
    implementation(libs.work.runtime)
    implementation(libs.hilt.work)
    ksp(libs.hilt.work.compiler)

    // Google Play Billing
    implementation("com.android.billingclient:billing-ktx:6.1.0")

    // US-213: Glance home-screen widget. The tier table advertises a widget on
    // both platforms, but only iOS had one.
    implementation(libs.glance.appwidget)
    implementation(libs.glance.material3)

    // Image Loading
    implementation(libs.coil.compose)

    // Logging
    implementation(libs.timber)

    // US-197: Firebase Cloud Messaging. The dependency compiles without
    // google-services.json; only the generated config resources are missing, which
    // PushRegistrationService handles.
    implementation(platform(libs.firebase.bom))
    implementation(libs.firebase.messaging)

    // US-199: crash reporting. SDK only — the Sentry Gradle plugin would need
    // SENTRY_AUTH_TOKEN at build time, which no contributor should require.
    implementation(libs.sentry.android)

    // Unit Testing
    testImplementation(libs.junit)
    testImplementation(libs.mockk)
    testImplementation(libs.truth)
    testImplementation(libs.turbine)
    testImplementation(libs.coroutines.test)
    testImplementation(libs.core.testing)
    testImplementation(libs.room.testing)
    // US-203: DeepLinkValidator uses android.net.Uri, which needs a real Android
    // runtime. Robolectric provides one on the JVM so the URI contract is covered
    // by fast unit tests rather than only by instrumented ones.
    testImplementation(libs.robolectric)

    // Android Testing — US-192: hilt-android-testing supplies HiltTestApplication,
    // which the custom runner in app/src/androidTest returns from newApplication().
    // Without it the runner cannot exist and connectedAndroidTest fails to configure.
    androidTestImplementation(libs.espresso)
    androidTestImplementation(libs.test.runner)
    androidTestImplementation(libs.test.rules)
    androidTestImplementation(libs.test.core)
    androidTestImplementation(libs.test.ext.junit)
    androidTestImplementation(libs.compose.ui.test.junit4)
    androidTestImplementation(libs.truth)
    androidTestImplementation(libs.hilt.android)
    androidTestImplementation(libs.hilt.android.testing)
    kspAndroidTest(libs.hilt.compiler)
}
