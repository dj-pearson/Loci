# Lociate ProGuard Rules

# Keep Supabase models
-keep class com.pearsonmedia.lociate.data.remote.dto.** { *; }

# Keep Room entities
-keep class com.pearsonmedia.lociate.data.local.entity.** { *; }

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
-keep,includedescriptorclasses class com.pearsonmedia.lociate.**$$serializer { *; }
-keepclassmembers class com.pearsonmedia.lociate.** {
    *** Companion;
}
-keepclasseswithmembers class com.pearsonmedia.lociate.** {
    kotlinx.serialization.KSerializer serializer(...);
}
