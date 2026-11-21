plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.rovikvpn.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.rovikvpn.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // ریشه‌ی اصلی «هسته هرگز استارت نمی‌خورد»:
    // پلاگین flutter_v2ray فایل libtun2socks.so را به‌صورت «فایل اجرایی»
    // از nativeLibraryDir اجرا می‌کند. با AGP جدید پیش‌فرض این است که
    // کتابخانه‌ها استخراج نشوند و مستقیم از داخل APK مپ شوند؛ در این حالت
    // آن مسیر وجود ندارد و tun2socks بی‌صدا اجرا نمی‌شود. APK سالم است
    // (فایل‌ها داخلش هستند) ولی روی گوشی استخراج نمی‌شوند.
    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }

    buildTypes {
        release {
            // R8 کلاس‌های gomobile ‏(go.* و libv2ray.*) را حذف/تغییر نام
            // می‌دهد و libgojni.so دیگر نمی‌تواند آن‌ها را با JNI پیدا کند.
            // برای اطمینان shrink خاموش است و قواعد keep هم اضافه شده.
            isMinifyEnabled = false
            isShrinkResources = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
