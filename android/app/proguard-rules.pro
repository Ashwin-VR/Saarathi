# ── Flutter ──────────────────────────────────────────────────────────────────
-keep class io.flutter.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.**

# ── Kotlin / Coroutines ───────────────────────────────────────────────────────
-keep class kotlin.** { *; }
-keep class kotlinx.** { *; }
-dontwarn kotlin.**
-dontwarn kotlinx.**

# ── AndroidX / Lifecycle ──────────────────────────────────────────────────────
-keep class androidx.** { *; }
-dontwarn androidx.**

# ── Google Play Services (location, maps) ────────────────────────────────────
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.android.gms.**

# ── SQLite / Drift ───────────────────────────────────────────────────────────
-keep class org.sqlite.** { *; }
-keep class org.sqlite.database.** { *; }

# ── BLE / Bluetooth ──────────────────────────────────────────────────────────
-keep class com.boskokg.flutter_blue_plus.** { *; }
-dontwarn com.boskokg.flutter_blue_plus.**

# ── Notifications ─────────────────────────────────────────────────────────────
-keep class com.dexterous.** { *; }
-dontwarn com.dexterous.**

# ── Share / File provider ─────────────────────────────────────────────────────
-keep class androidx.core.content.FileProvider
-keep class com.mr.flutter.plugin.sharefile.** { *; }

# ── General: keep enums intact ───────────────────────────────────────────────
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}

# ── General: keep Parcelables ────────────────────────────────────────────────
-keepclassmembers class * implements android.os.Parcelable {
    public static final android.os.Parcelable$Creator CREATOR;
}

# ── Prevent R8 from removing reflection-accessed members ─────────────────────
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes EnclosingMethod
-keepattributes InnerClasses
