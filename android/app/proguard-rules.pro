# Flutter default rules
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Keep all classes that might be accessed via JNI
-keep class com.KongComic.reader.** { *; }

# Keep serialization classes
-keepclassmembers class * {
    @com.google.gson.annotations.SerializedName <fields>;
}

# Play Core (SplitCompat)
-keep class com.google.android.play.core.** { *; }
-dontwarn com.google.android.play.core.**
