# Lociate ProGuard Rules

# Keep Supabase models
-keep class app.lociate.android.data.remote.dto.** { *; }

# Keep Room entities
-keep class app.lociate.android.data.local.entity.** { *; }

# Ktor
-keep class io.ktor.** { *; }
-dontwarn io.ktor.**

# Kotlinx Serialization
-keepattributes *Annotation*, InnerClasses
-dontnote kotlinx.serialization.AnnotationsKt
-keepclassmembers class kotlinx.serialization.json.** {
    *** Companion;
}
-keepclasseswithmembers class kotlinx.serialization.json.** {
    kotlinx.serialization.KSerializer serializer(...);
}
-keep,includedescriptorclasses class app.lociate.android.**$$serializer { *; }
-keepclassmembers class app.lociate.android.** {
    *** Companion;
}
-keepclasseswithmembers class app.lociate.android.** {
    kotlinx.serialization.KSerializer serializer(...);
}
