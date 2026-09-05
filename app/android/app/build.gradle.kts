plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// google-services.json is a user-provided file (Milestone 15 setup, never
// committed -- see .gitignore). Applying this plugin unconditionally fails
// the ENTIRE Android build (not just push notifications) the moment the
// file is absent, which would regress every prior milestone for a fresh
// clone. Gate it on the file's presence instead -- main.dart's own
// Firebase.initializeApp() try/catch already handles the resulting
// "Firebase not configured" case gracefully at the Dart level; this just
// lets the build reach that point at all.
if (rootProject.file("app/google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
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
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
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
