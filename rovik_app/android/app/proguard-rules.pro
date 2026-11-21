# هسته Xray (gomobile) و پلاگین flutter_v2ray — با JNI/reflection صدا زده می‌شوند.
-keep class go.** { *; }
-keep class libv2ray.** { *; }
-keep class com.github.blueboytm.flutter_v2ray.** { *; }
-keepclasseswithmembernames class * {
    native <methods>;
}
-dontwarn go.**
-dontwarn libv2ray.**
