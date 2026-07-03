# ML Kit optional language model classes not bundled in this APK
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**

# Play Core deferred component classes (not used — direct install only)
-dontwarn com.google.android.play.core.tasks.**
-dontwarn com.google.android.play.core.**

# ML Kit internal service registrars must survive R8 (loaded via reflection)
-keep class com.google.mlkit.** { *; }

# Keep Flutter wrapper classes
-keep class io.flutter.** { *; }
-keep class io.flutter.plugin.** { *; }
