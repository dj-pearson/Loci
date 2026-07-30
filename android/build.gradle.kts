plugins {
    alias(libs.plugins.android.application) apply false
    alias(libs.plugins.kotlin.android) apply false
    alias(libs.plugins.kotlin.compose) apply false
    alias(libs.plugins.hilt.android) apply false
    alias(libs.plugins.ksp) apply false
    alias(libs.plugins.kotlin.serialization) apply false
    // US-197: applied conditionally in app/build.gradle.kts — google-services.json
    // is gitignored, and this plugin fails the build outright when it is absent.
    alias(libs.plugins.google.services) apply false
}
