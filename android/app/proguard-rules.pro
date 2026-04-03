# Loci ProGuard Rules

# Keep Supabase models
-keep class com.pearsonmedia.loci.data.remote.dto.** { *; }

# Keep Room entities
-keep class com.pearsonmedia.loci.data.local.entity.** { *; }

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
-keep,includedescriptorclasses class com.pearsonmedia.loci.**$$serializer { *; }
-keepclassmembers class com.pearsonmedia.loci.** {
    *** Companion;
}
-keepclasseswithmembers class com.pearsonmedia.loci.** {
    kotlinx.serialization.KSerializer serializer(...);
}
