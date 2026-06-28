# Flutter default rules
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Keep all classes that might be accessed via JNI
-keep class com.KongComic.reader.** { *; }

# Keep serialization classes
-keepclassmembers class * {
    @com.google.gson.annotations.SerializedName <fields>;
}

# Keep Gson type info
-keepattributes Signature
-keepattributes *Annotation*
-keep class com.google.gson.** { *; }
-keep class * implements com.google.gson.TypeAdapterFactory
-keep class * implements com.google.gson.JsonSerializer
-keep class * implements com.google.gson.JsonDeserializer

# Play Core (SplitCompat)
-keep class com.google.android.play.core.** { *; }
-dontwarn com.google.android.play.core.**
