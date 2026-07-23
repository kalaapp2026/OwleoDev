pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    // Pinned below AGP 9.0: AGP 9.x forbids plugins applying their own legacy
    // 'org.jetbrains.kotlin.android' (audioplayers_android does), while several other pinned
    // plugins (file_picker, share_plus) don't get their Kotlin sources picked up at all under
    // AGP 9's alternative (android.builtInKotlin=true) - a genuine three-way incompatibility with
    // this generation of plugin versions. 8.7.3/2.1.0 is the last well-supported combo before that.
    id("com.android.application") version "8.11.1" apply false
    id("org.jetbrains.kotlin.android") version "2.1.20" apply false
}

include(":app")
