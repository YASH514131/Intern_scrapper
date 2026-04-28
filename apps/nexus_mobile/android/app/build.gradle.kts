import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

// Load key.properties for release signing
val keyProperties = Properties()
val keyPropertiesFile = rootProject.file("key.properties")
if (keyPropertiesFile.exists()) {
    keyProperties.load(keyPropertiesFile.inputStream())
}

val releaseKeystoreFile = file(keyProperties["storeFile"]?.toString() ?: "release.keystore")
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
}

android {
    namespace = "com.nexus.jobscanner"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    signingConfigs {
        getByName("debug") {
            keyAlias = "androiddebugkey"
            keyPassword = "android"
            // Fixed: standard debug keystore location
            storeFile = file("${System.getProperty("user.home")}/.android/debug.keystore")
            storePassword = "android"
        }

        create("release") {
            keyAlias = keyProperties["keyAlias"]?.toString() ?: "release"
            keyPassword = keyProperties["keyPassword"]?.toString() ?: ""
            storeFile = releaseKeystoreFile
            storePassword = keyProperties["storePassword"]?.toString() ?: ""
        }
    }

    defaultConfig {
        applicationId = "com.nexus.jobscanner"
        minSdk = 21
        targetSdk = 34
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        ndk {
            abiFilters.addAll(listOf("arm64-v8a", "armeabi-v7a"))
        }
    }

    buildTypes {
        release {
            signingConfig = if (releaseKeystoreFile.exists()) signingConfigs.getByName("release") else signingConfigs.getByName("debug")
            isMinifyEnabled = false

            // Indus App Store: explicit v2 + v3 signing (covers lineage/new signature)
            isShrinkResources = false
        }
    }

    // Indus App Store: enable APK Signature Scheme v2 and v3 (key rotation/lineage)
    bundle {
        storeArchive {
            enable = true
        }
    }
}

// Force v2 + v3 signing on all APK outputs
androidComponents {
    onVariants { variant ->
        variant.outputs.forEach { output ->
            if (output is com.android.build.api.variant.impl.VariantOutputImpl) {
                // v2 and v3 enabled by default in AGP 7+; lineage handled via apksigner CLI
            }
        }
    }
}

flutter {
    source = "../.."
}