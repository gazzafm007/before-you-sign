import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing. Codemagic supplies CM_KEYSTORE_PATH etc. from the upload
// key stored in Codemagic; on a PC, put the same details in
// android/key.properties (never commit that file or the .jks).
val keyProps = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
fun signingValue(env: String, prop: String): String? =
    System.getenv(env)?.takeIf { it.isNotBlank() } ?: keyProps.getProperty(prop)
val uploadStore = signingValue("CM_KEYSTORE_PATH", "storeFile")

android {
    namespace = "com.arpra.before_you_sign"
    compileSdk = maxOf(36, flutter.compileSdkVersion)
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Clear to Sign by ARPRA (store ID; cannot change after publishing).
        applicationId = "com.arpra.cleartosign"
        minSdk = maxOf(24, flutter.minSdkVersion)
        // Google Play: new apps and updates must target Android 16 (API 36)
        // from 31 August 2026.
        targetSdk = 36
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (uploadStore != null) {
            create("upload") {
                storeFile = file(uploadStore)
                storePassword = signingValue("CM_KEYSTORE_PASSWORD", "storePassword")
                keyAlias = signingValue("CM_KEY_ALIAS", "keyAlias")
                keyPassword = signingValue("CM_KEY_PASSWORD", "keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // Upload key when available; otherwise debug keys (test builds only:
            // Google Play rejects debug-signed bundles).
            signingConfig = if (uploadStore != null) signingConfigs.getByName("upload")
                            else signingConfigs.getByName("debug")
            // Code shrinking (R8) breaks Google's ML Kit document scanner (used by
            // cunning_document_scanner on Android): the
            // scanner fails to start with a NullPointerException inside
            // GmsDocumentScanning.getClient. Keep shrinking off until we have
            // keep rules that are proven on a device.
            isMinifyEnabled = false
            isShrinkResources = false
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
