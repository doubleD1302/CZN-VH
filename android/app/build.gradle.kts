import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val secrets = Properties().apply { val f = rootProject.file("../.signing/release.properties"); if (f.exists()) f.inputStream().use { load(it) } }

android {
    buildFeatures { aidl = true }
    namespace = "vn.czn.viethoa.czn_patcher"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "vn.czn.viethoa.localadb"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (secrets.containsKey("storeFile")) create("community") {
            storeFile = rootProject.file(secrets.getProperty("storeFile"))
            storePassword = secrets.getProperty("storePassword")
            keyAlias = secrets.getProperty("keyAlias")
            keyPassword = secrets.getProperty("keyPassword")
        }
    }

    buildTypes {
        release {
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            // Community releases use the persistent private release certificate.
            signingConfig = signingConfigs.findByName("community")
        }
    }

    testOptions {
        unitTests.isReturnDefaultValues = true
    }
}

dependencies {
    implementation("com.github.MuntashirAkon:libadb-android:3.1.1")
    implementation("org.bouncycastle:bcprov-jdk15to18:1.81")
    implementation("org.conscrypt:conscrypt-android:2.5.3")
    implementation("dev.rikka.shizuku:api:13.1.5")
    implementation("dev.rikka.shizuku:provider:13.1.5")
    implementation("org.lz4:lz4-java:1.8.0")
    implementation("androidx.work:work-runtime:2.10.1")
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20240303")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}


gradle.taskGraph.whenReady { if (allTasks.any { it.name == "assembleRelease" || it.name == "bundleRelease" }) require(secrets.containsKey("storeFile")) { "Missing .signing/release.properties; refusing an unsigned release." } }
