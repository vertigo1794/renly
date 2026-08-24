plugins {
    id("com.android.application")
    id("kotlin-android")
    id("com.google.gms.google-services")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.renly.renly"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.renly.renly"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
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

dependencies {
    // Required by the Theme.MaterialComponents.* parents this module's own
    // res/values/styles.xml and res/values-night/styles.xml now use (needed
    // so Stripe's PaymentSheet has an AppCompat-descendant theme to inflate
    // under). This IS already on the runtime classpath transitively -- the
    // stripe_android plugin declares
    // `implementation 'com.google.android.material:material:1.6.0'` -- but a
    // theme parent referenced from THIS module's resources should not depend
    // on another module's private `implementation` dependency continuing to
    // exist. Declared explicitly so the resource reference cannot break if
    // flutter_stripe ever drops or renames it. Gradle resolves to the
    // highest requested version, so this also supersedes the 1.6.0 above.
    implementation("com.google.android.material:material:1.12.0")
}
