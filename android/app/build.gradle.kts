import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android Gradle plugin.
    // Kotlin support is provided by Flutter's Built-in Kotlin (no need to apply
    // org.jetbrains.kotlin.android / kotlin-android directly).
    // See https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin/for-app-developers
    id("dev.flutter.flutter-gradle-plugin")
}

// Run scripts/build_android.sh before each Android build so the wellen
// shared libraries are always up to date and present in jniLibs/. Without
// this, the .so files must be built manually after every Rust change and
// every fresh clone — and a new dev gets a "Failed to load waveform"
// fallback prompt because libwellen_ffi.so is missing from the APK.
//
// The script is idempotent and incremental: cargo skips work when the Rust
// crate hasn't changed, so the cost on repeat builds is just the script's
// startup overhead.
//
// CI / device-class targeting note: the script always builds all three
// ABIs (arm64-v8a, armeabi-v7a, x86_64). Restrict the runtime APK to a
// subset via `ndk.abiFilters` if needed — the .so files are inert when
// not loaded.
//
// libwellen_ffi.so also carries the LXT/LXT2 converter (wellen_ffi links the
// sibling lxt2fst crate, which uses the vendored fst-writer), so those crates
// are task inputs too — without them an lxt2fst change leaves Gradle
// treating the task as up to date and the stale .so ships.
val buildWellenAndroid by tasks.registering(Exec::class) {
    val repoRoot = rootProject.projectDir.parentFile
    workingDir = repoRoot
    commandLine("bash", "scripts/build_android.sh")
    // Touch a marker so Gradle's up-to-date check sees this task ran.
    val marker = layout.buildDirectory.file("wellen-android-built").get().asFile
    outputs.file(marker)
    inputs.dir(repoRoot.resolve("native/wellen_ffi/src"))
    inputs.file(repoRoot.resolve("native/wellen_ffi/Cargo.toml"))
    inputs.file(repoRoot.resolve("native/wellen_ffi/Cargo.lock"))
    inputs.dir(repoRoot.resolve("native/lxt2fst/src"))
    inputs.file(repoRoot.resolve("native/lxt2fst/Cargo.toml"))
    inputs.dir(repoRoot.resolve("native/vendor/fst-writer/src"))
    inputs.file(repoRoot.resolve("native/vendor/fst-writer/Cargo.toml"))
    doLast {
        marker.parentFile.mkdirs()
        marker.writeText(System.currentTimeMillis().toString())
    }
}

tasks.named("preBuild").configure {
    dependsOn(buildWellenAndroid)
}

// Release signing config, loaded from android/key.properties when present
// (gitignored — the upload keystore + passwords live OUTSIDE the repo). Absent
// on dev machines and CI, where release falls back to debug signing below.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

android {
    namespace = "com.ferriteengineering.wavecrux"
    compileSdk = flutter.compileSdkVersion

    // NDK r28c — matches Flutter's default and the version used by scripts/build_android.sh
    // to cross-compile the wellen_ffi Rust library for Android targets.
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.ferriteengineering.wavecrux"

        // Android 7.0+ (API 24). Covers >99% of active Android devices.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            // Populated only when android/key.properties exists. The upload
            // keystore + passwords live OUTSIDE the repo; see
            // scripts/release_android.sh and android/key.properties.example.
            keyAlias = keystoreProperties.getProperty("keyAlias")
            keyPassword = keystoreProperties.getProperty("keyPassword")
            storeFile = keystoreProperties.getProperty("storeFile")?.let { file(it) }
            storePassword = keystoreProperties.getProperty("storePassword")
        }
    }

    buildTypes {
        release {
            // Sign with the upload keystore from android/key.properties when present
            // (required for a Play-uploadable AAB — see scripts/release_android.sh);
            // otherwise fall back to debug signing so `flutter run --release` and CI
            // (which have no keystore) still build.
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }

            // R8 minification and resource shrinking for release APK/AAB.
            // ProGuard rules preserve Flutter embedding, FFI loading, and native JNI symbols.
            isMinifyEnabled = true
            isShrinkResources = true
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

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}
