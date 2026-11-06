import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Google Maps SDK key — read from the untracked android/local.properties
// (MAPS_API_KEY=...) or the MAPS_API_KEY environment variable, never
// committed. See android/maps_api_key.example. A release build without
// it fails; debug still builds (the embedded map just can't load tiles).
val mapsApiKey: String = run {
    val props = Properties()
    val file = rootProject.file("local.properties")
    if (file.exists()) file.inputStream().use { props.load(it) }
    (props.getProperty("MAPS_API_KEY") ?: System.getenv("MAPS_API_KEY") ?: "").trim()
}

if (mapsApiKey.isEmpty() &&
    gradle.startParameter.taskNames.any { it.contains("Release", ignoreCase = true) }
) {
    throw GradleException(
        "MAPS_API_KEY is not set. Add MAPS_API_KEY=... to android/local.properties " +
            "(see android/maps_api_key.example) or export it as an environment variable.",
    )
}

// Release signing — the Play upload key, configured in the untracked
// android/key.properties (storeFile, storePassword, keyAlias, keyPassword),
// never committed. A release build without it fails instead of silently
// falling back to the Android Debug key, which Google Play rejects.
val keystoreProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}
val hasReleaseKeystore = keystoreProperties.getProperty("storeFile") != null

if (!hasReleaseKeystore &&
    gradle.startParameter.taskNames.any { it.contains("Release", ignoreCase = true) }
) {
    throw GradleException(
        "Release signing is not configured. Add android/key.properties with " +
            "storeFile, storePassword, keyAlias and keyPassword of the upload keystore.",
    )
}

// MEREYTOI TEST: the side-by-side copy (see docs/android-builds.md). The real
// app's package, label and signing don't change unless this is passed, and it
// is signed by the same upload key, so its Google Maps entry stays valid across
// rebuilds. Use flutter/tool/build_test_apk.sh rather than passing it by hand.
val mereytoiTest = project.hasProperty("mereytoiTest")

android {
    namespace = "kz.mereytoi.mereytoi_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "kz.mereytoi.mereytoi_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        manifestPlaceholders["MAPS_API_KEY"] = mapsApiKey
        manifestPlaceholders["appLabel"] = if (mereytoiTest) "MEREYTOI TEST" else "MEREYTOI"
        if (mereytoiTest) applicationIdSuffix = ".qa"
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            if (hasReleaseKeystore) {
                signingConfig = signingConfigs.getByName("release")
            }
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
