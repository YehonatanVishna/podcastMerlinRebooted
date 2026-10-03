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
    id("com.android.application") version "9.0.1" apply false
    id("org.jetbrains.kotlin.android") version "2.3.20" apply false
}

include(":app")

// Workaround for AGP 9 / Gradle 9 compatibility with home_widget (0.7.0):
// home_widget's build.gradle uses legacy `apply plugin: 'kotlin-android'`, which fails
// under Gradle 9.0+ / AGP 9.0+. We dynamically patch it to use `pluginManager.apply('kotlin-android')`.
// TODO(upstream): Remove once home_widget releases an AGP 9-compatible update.
findProject(":home_widget")?.let { hwProject ->
    val buildFile = File(hwProject.projectDir, "build.gradle")
    if (buildFile.exists()) {
        try {
            val content = buildFile.readText()
            if (content.contains("apply plugin: 'kotlin-android'")) {
                buildFile.writeText(
                    content.replace(
                        "apply plugin: 'kotlin-android'",
                        "pluginManager.apply('kotlin-android')"
                    )
                )
            }
        } catch (_: Exception) {
            // Ignore if pub cache is read-only
        }
    }
}
