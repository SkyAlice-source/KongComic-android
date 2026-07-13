# Flutter's own keep rules
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# Keep the native method channel
-keep class com.skyalien.** { *; }

# Keep the Flutter Firebase Auth plugin
-keep class io.flutter.plugins.firebase.** { *; }

# Keep the Android support library
-keep class android.support.** { *; }

# Keep the Kotlin serialization
-keepattributes *Annotation*, InnerClasses
-dontnote kotlinx.serialization.AnnotationsKt

-keepclassmembers class kotlinx.serialization.json.** {
    *** Companion;
}
-keepclasseswithmembers class kotlinx.serialization.json.** {
    kotlinx.serialization.KSerializer serializer(...);
}

-keep,includedescriptorclasses class com.skyalien.**$$serializer { *; }
-keepclassmembers class com.skyalien.** {
    *** Companion;
}
-keepclasseswithmembers class com.skyalien.** {
    kotlinx.serialization.KSerializer serializer(...);
}

# Play Core (SplitCompat)
-keep class com.google.android.play.core.** { *; }
-dontwarn com.google.android.play.core.**

# flutter_qjs — accessed via JNI from Dart
-keep class com.whl.quickjs.** { *; }

# sqlite3 — native lib loaded via dart:ffi
-keep class com.gsochernjakov.sqlite3_flutter_libs.** { *; }

# flutter_7zip — native lib loaded via dart:ffi
-keep class com.xv01.flutter_7zip.** { *; }

# lodepng_flutter — native lib loaded via dart:ffi
-keep class com.xv01.lodepng_flutter.** { *; }

# flutter_local_notifications — reflection-based plugin registration
-keep class com.dexterous.flutterlocalnotifications.** { *; }

# flutter_background_service — isolate service via reflection
-keep class com.bbflight.background_download.** { *; }
