# LenzNode Hardened R8 / ProGuard Rules
-repackageclasses 'l'
-allowaccessmodification
-overloadaggressively

# Strip debug/verbose logging in release builds
-assumenosideeffects class android.util.Log {
    public static boolean isLoggable(java.lang.String, int);
    public static int v(...);
    public static int d(...);
    public static int i(...);
}

# Preserve AndroidManifest entry points
-keep public class com.lenznode.app.MainActivity
-keep public class com.lenznode.app.service.LenzServerService

# Preserve WebView JavascriptInterface callbacks if added
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}

# Preserve ViewBinding static inflate entry points
-keepclassmembers class * implements androidx.viewbinding.ViewBinding {
    public static *** inflate(...);
}

-keepattributes SourceFile,LineNumberTable
