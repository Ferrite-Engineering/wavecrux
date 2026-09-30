# ProGuard / R8 rules for WaveCrux Android release builds.
#
# The wellen_ffi Rust library is loaded at runtime as a native .so via
# dart:ffi DynamicLibrary.open('libwellen_ffi.so'). R8 does not touch .so
# files, but these rules prevent stripping of the Flutter embedding and
# plugin classes that orchestrate native library loading.

# ── Flutter embedding ──────────────────────────────────────────────────────────

-keep class io.flutter.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.app.** { *; }

# ── Application classes ────────────────────────────────────────────────────────

-keep class com.ferriteengineering.wavecrux.** { *; }

# ── Native / JNI methods ───────────────────────────────────────────────────────

# Keep all classes with native methods so R8 does not remove the JNI bridge
# declarations (required for Flutter's own native-to-Java callbacks).
-keepclasseswithmembernames,includedescriptorclasses class * {
    native <methods>;
}

# ── Reflection and annotations ────────────────────────────────────────────────

# Flutter plugins and the Dart runtime rely on annotations and reflection.
-keepattributes *Annotation*
-keepattributes EnclosingMethod
-keepattributes InnerClasses
-keepattributes Signature
-keepattributes Exceptions

# ── Suppress known-harmless warnings ──────────────────────────────────────────

-dontwarn kotlin.**
-dontwarn kotlinx.**
-dontwarn org.jetbrains.**

# Flutter's embedding references Google Play Core classes (deferred components /
# Play Feature Delivery) that are only on the classpath when the app actually
# uses Play Feature Delivery. WaveCrux does not, so R8 reports them as missing
# classes and aborts minification (the FlutterPlayStoreSplitApplication /
# PlayStoreDeferredComponentManager code paths are never exercised). Tell R8 to
# ignore them.
-dontwarn com.google.android.play.core.**
