# Flutter default rules
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# App 自身代码：以前整包 `-keep com.KongComic.reader.** { *; }`，等于完全不
# 混淆，R8 的瘦身/内联优化对自有代码一律失效。收窄为只保留真正的反射入口：
# - MainActivity：由 framework 反射实例化，且承载 MethodChannel/EventChannel，
#   类名与成员都不能被重命名；
# - JNI 入口：当前无 native 方法，保留规则以防后续新增。
# 其余自有类（含匿名内部类）交给 R8 正常优化。
-keep class com.KongComic.reader.MainActivity { *; }
-keepclassmembers class com.KongComic.reader.** {
    native <methods>;
}

# Manifest 里声明的 Receiver/Provider，AGP 会自动保留；但
# flutter_local_notifications 的广播回调类不在 io.flutter.plugins 包下，
# 显式保留避免被重命名后通知点击失效。
-keep class com.dexterous.flutterlocalnotifications.** { *; }

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
