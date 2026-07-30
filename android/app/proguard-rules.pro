# Keep Flutter engine and plugin reflection.
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Keep method channel entry points.
-keep class com.example.secure_p2p_messenger.MainActivity { *; }

# Remove log calls in release.
-assumenosideeffects class android.util.Log {
    public static int v(...);
    public static int d(...);
    public static int i(...);
    public static int w(...);
    public static int e(...);
}
