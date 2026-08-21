plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.delivery.dmm_delivery"
    compileSdk = flutter.compileSdkVersion
    // The "jni" plugin (a transitive dep pulled in via file_picker/flutter_map)
    // needs 28.2.13676358 specifically - pin to it explicitly rather than
    // relying on Gradle's automatic "use the highest available" fallback.
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.delivery.dmm_delivery"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        getByName("debug") {
            // A project-scoped debug keystore, not the machine-wide
            // ~/.android/debug.keystore - its SHA-1 is registered directly
            // against this app's Firebase project, so Google Sign-In works
            // for every developer who builds from this checkout, regardless
            // of what other projects' debug keys happen to be on their
            // machine. Password is the Android-tooling debug-keystore
            // convention ("android"/"android"); it's not a real secret.
            storeFile = file("dmm_delivery_debug.keystore")
            storePassword = "android"
            keyAlias = "androiddebugkey"
            keyPassword = "android"
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}
