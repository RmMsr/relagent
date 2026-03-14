import com.android.build.gradle.internal.api.ApkVariantOutputImpl
import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}


// Signing config resolved from env vars (CI) with fallback to key.properties (local dev).
// Env vars: ANDROID_KEYSTORE_PATH, ANDROID_KEYSTORE_PASSWORD, ANDROID_KEY_ALIAS, ANDROID_KEY_PASSWORD
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

fun signingValue(envVar: String, propertyKey: String): String? =
    System.getenv(envVar) ?: keystoreProperties[propertyKey] as? String

val signingKeystorePath = signingValue("ANDROID_KEYSTORE_PATH", "storeFile")
val signingKeystorePassword = signingValue("ANDROID_KEYSTORE_PASSWORD", "storePassword")
val signingKeyAlias = signingValue("ANDROID_KEY_ALIAS", "keyAlias") ?: "signing"
val signingKeyPassword = signingValue("ANDROID_KEY_PASSWORD", "keyPassword") ?: signingKeystorePassword
val hasSigningConfig = signingKeystorePath != null && signingKeystorePassword != null
val allowUnsignedRelease = System.getenv("ANDROID_ALLOW_UNSIGNED_RELEASE") == "true"

android {
    namespace = "org.venkado.relagent"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    buildFeatures {
        buildConfig = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "org.venkado.relagent"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Add one digit to version code to seperate platforms
        versionCode = flutter.versionCode.toInt() * 10
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasSigningConfig) {
            create("release") {
                keyAlias = signingKeyAlias
                keyPassword = signingKeyPassword
                storeFile = signingKeystorePath?.let { file(it) }
                storePassword = signingKeystorePassword
            }
        }
    }

    buildTypes {
        debug {
            applicationIdSuffix = ".debug"
            buildConfigField("boolean", "DEBUG", "true")
        }
        release {
            buildConfigField("boolean", "DEBUG", "false")
            if (hasSigningConfig) {
                signingConfig = signingConfigs.getByName("release")
            } else if (allowUnsignedRelease) {
                println("Warning: building unsigned release (ANDROID_ALLOW_UNSIGNED_RELEASE=true)")
            } else {
                throw GradleException(
                    "Signing config missing for release build. " +
                    "Provide ANDROID_KEYSTORE_PATH, ANDROID_KEYSTORE_PASSWORD env or key.properties file. " +
                    "For an unsigned build set ANDROID_ALLOW_UNSIGNED_RELEASE=true."
                )
            }
        }
    }
}

flutter {
    source = "../.."
}

// Overrides default Flutter split ABI version scheme. The last digit indicates the platform:
// 0 = AAB (Android App Bundle) or universal APK
// 1 = armeabi-v7a APK
// 2 = arm64-v8a APK
// 4 = x86_64 APK
val abiCodes = mapOf("armeabi-v7a" to 1, "arm64-v8a" to 2, "x86_64" to 4)
android.applicationVariants.configureEach {
    val variant = this
    variant.outputs.forEach { output ->
        val abiVersionCode = abiCodes[output.filters.find { it.filterType == "ABI" }?.identifier]
        if (abiVersionCode != null) {
            (output as ApkVariantOutputImpl).versionCodeOverride = variant.versionCode + abiVersionCode
        }
    }
}
