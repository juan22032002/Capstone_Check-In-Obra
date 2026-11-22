import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Firma de release. Los datos salen de variables de entorno (el CI, desde sus
// secretos) o, en local, de `android/key.properties`, que no se versiona. El
// keystore nunca vive en el repo: con él se podría firmar una app que se haga
// pasar por esta.
val clavesLocales = Properties().apply {
    val archivo = rootProject.file("key.properties")
    if (archivo.exists()) archivo.inputStream().use { load(it) }
}

fun dato(entorno: String, propiedad: String): String? =
    (System.getenv(entorno) ?: clavesLocales.getProperty(propiedad))?.takeIf { it.isNotBlank() }

val keystoreArchivo = dato("CHECKINOBRA_KEYSTORE_FILE", "storeFile")
val keystoreClave = dato("CHECKINOBRA_KEYSTORE_PASSWORD", "storePassword")
val keystoreAlias = dato("CHECKINOBRA_KEY_ALIAS", "keyAlias")
val keystoreAliasClave = dato("CHECKINOBRA_KEY_PASSWORD", "keyPassword")
val hayKeystore = listOf(keystoreArchivo, keystoreClave, keystoreAlias, keystoreAliasClave).all { it != null }

android {
    namespace = "cl.duocuc.checkinobra_mobile"
    // flutter.compileSdkVersion queda en 36, pero flutter_secure_storage exige 37.
    // compileSdk es retrocompatible: subirlo no cambia el comportamiento en runtime
    // (eso lo controla targetSdk) ni los dispositivos soportados (minSdk).
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "cl.duocuc.checkinobra_mobile"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hayKeystore) {
            create("release") {
                storeFile = rootProject.file(keystoreArchivo!!)
                storePassword = keystoreClave
                keyAlias = keystoreAlias
                keyPassword = keystoreAliasClave
            }
        }
    }

    buildTypes {
        release {
            // Nunca la clave de debug: cualquiera tiene la misma, así que un
            // APK firmado con ella no prueba quién lo publicó (hallazgo S-20).
            signingConfig = if (hayKeystore) signingConfigs.getByName("release") else null
        }
    }
}

// Un release sin keystore no sale firmado y Flutter lo informaría recién al
// instalarlo; mejor cortar acá y decir qué falta.
gradle.taskGraph.whenReady {
    val pideRelease = allTasks.any { it.project == project && it.name in setOf("assembleRelease", "bundleRelease") }
    if (pideRelease && !hayKeystore) {
        throw GradleException(
            "Falta el keystore de firma. Define CHECKINOBRA_KEYSTORE_FILE, " +
                "CHECKINOBRA_KEYSTORE_PASSWORD, CHECKINOBRA_KEY_ALIAS y " +
                "CHECKINOBRA_KEY_PASSWORD, o crea android/key.properties con " +
                "storeFile, storePassword, keyAlias y keyPassword. " +
                "Ver mobile/README.md."
        )
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
