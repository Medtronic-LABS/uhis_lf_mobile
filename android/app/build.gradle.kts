import java.util.Properties

// Parse --dart-define values forwarded by the Flutter Gradle plugin.
// Each entry is base64-encoded "KEY=VALUE"; joined as a comma-separated string.
fun parseDartDefines(project: Project): Map<String, String> {
    val raw = project.findProperty("dart-defines") as? String ?: return emptyMap()
    return raw.split(",").mapNotNull { encoded ->
        runCatching {
            val decoded = String(java.util.Base64.getDecoder().decode(encoded.trim()))
            val idx = decoded.indexOf('=')
            if (idx < 0) null else decoded.substring(0, idx) to decoded.substring(idx + 1)
        }.getOrNull()
    }.toMap()
}

val dartDefines = parseDartDefines(project)

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
val hasReleaseKeystore = keystorePropertiesFile.exists()
if (hasReleaseKeystore) {
    keystoreProperties.load(keystorePropertiesFile.inputStream())
}

android {
    namespace = "com.medtroniclabs.uhis_next"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    buildFeatures {
        buildConfig = true
    }

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        multiDexEnabled = true
        // Expose API_BASE_URL from --dart-define so native Kotlin can build
        // service-specific URLs (e.g. coaching backend) without hardcoding a host.
        buildConfigField(
            "String", "API_BASE_URL",
            "\"${dartDefines["API_BASE_URL"] ?: "https://spice-dev-backend.uhis.labsplatform.com/"}\""
        )
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.medtroniclabs.uhis_next"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // 24+ required: MediaPipe tasks-genai (bundled in micro-coaching-sdk.aar) needs API 24.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Real field devices are essentially never x86_64/x86 — only emulators and
        // Chromebooks are. Applies to every build type (AGP has no per-build-type ABI
        // filter), so debug/profile builds on an x86_64 emulator will no longer install.
        ndk {
            abiFilters += setOf("arm64-v8a", "armeabi-v7a")
        }
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // Falls back to the debug key only when android/key.properties is absent (e.g. a
            // fresh clone without the upload keystore) so `flutter run --release` still works.
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
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

configurations.all {
    // audio_waveforms pulls in exoplayer2.ui which ships exo_player_view.xml with old class names.
    // Media3's PlayerView inflates the same resource name → ClassCastException. Exclude the UI
    // module; audio_waveforms only needs the player core, not the ExoPlayer2 UI layer.
    exclude(group = "com.google.android.exoplayer", module = "exoplayer-ui")
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    implementation("androidx.core:core-splashscreen:1.0.1")
    // enableEdgeToEdge() — explicit opt-in the Play Console SDK 35 static
    // check looks for; don't rely on the version pulled in transitively via
    // FlutterFragmentActivity -> FragmentActivity.
    implementation("androidx.activity:activity-ktx:1.9.3")

    // ── Micro-coaching SDK (prebuilt AAR) ─────────────────────────────────────
    implementation(files("libs/micro-coaching-sdk.aar"))
    // OpenTelemetry API stub — SDK AAR's TelemetryManager links against this at
    // runtime; the API jar satisfies class resolution without wiring any exporter.
    implementation("io.opentelemetry:opentelemetry-api:1.48.0")
    // Transitive runtime deps (AAR does not bundle them)
    implementation("androidx.appcompat:appcompat:1.7.0")
    implementation("com.google.android.material:material:1.12.0")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.7")
    implementation("androidx.lifecycle:lifecycle-viewmodel-ktx:2.8.7")
    implementation("androidx.startup:startup-runtime:1.2.0")
    implementation("org.jetbrains:markdown:0.7.3")
    implementation("io.coil-kt:coil-compose:2.7.0")
    implementation("androidx.media3:media3-exoplayer:1.4.1")
    implementation("androidx.media3:media3-ui:1.4.1")
    implementation("io.github.petretiandrea:android-pdf-viewer:4.0.0")
    implementation(platform("androidx.compose:compose-bom:2025.08.00"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-graphics")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.activity:activity-compose:1.10.1")
    implementation("androidx.navigation:navigation-compose:2.8.9")
    implementation("androidx.room:room-runtime:2.7.0")
    implementation("androidx.room:room-ktx:2.7.0")
    implementation("androidx.work:work-runtime-ktx:2.10.1")

    implementation("com.google.mediapipe:tasks-genai:0.10.24")
    implementation("com.google.mlkit:translate:17.0.3")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("com.squareup.okhttp3:logging-interceptor:4.12.0")
    implementation("com.squareup.retrofit2:retrofit:2.11.0")
    implementation("com.squareup.retrofit2:converter-kotlinx-serialization:2.11.0")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.8.1")
    implementation("org.apache.commons:commons-compress:1.27.1")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.2")
}
