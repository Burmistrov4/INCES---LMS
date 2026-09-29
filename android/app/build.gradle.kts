plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.inces.inces_lms_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.inces.inces_lms_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // `maxOf(..., 23)` y no `23` a secas, ni `flutter.minSdkVersion` a secas.
        //
        // El paquete `mobile_scanner` declara `minSdk = 23` en su librería de
        // Android (medido en su `android/build.gradle.kts`, no supuesto). Si la
        // app declarara menos, el *manifest merger* aborta con
        // «uses-sdk:minSdkVersion N cannot be smaller than version 23 declared in
        // library». Y `flutter.minSdkVersion` lo fija Flutter y **cambia con la
        // versión**, así que confiar en él es confiar en que un día no baje.
        //
        // `maxOf` es **monótono**: garantiza >= 23 y **nunca baja** lo que diga
        // Flutter. No hay caso en el que empeore nada, y por eso se escribe así en
        // vez de elegir un número.
        //
        // **Medido, para que nadie lea esto como un arreglo de algo roto:** con
        // Flutter 3.47.0 (el que fija el CI) `flutter.minSdkVersion` vale **24**
        // —leído en `packages/flutter_tools/gradle/.../FlutterExtension.kt`—, así
        // que hoy esta expresión **evalúa a 24 y no cambia nada**. Es una guardia
        // para el día en que Flutter baje su suelo, no un fallo que estuviera
        // rompiendo el build.
        //
        // Por el mismo archivo: `flutter.compileSdkVersion` vale **36**, que es
        // exactamente el `compileSdk` que declara la librería del paquete (y sus
        // `androidx.camera:1.6.1`). O sea que **tampoco hay que subir
        // `compileSdk`**; queda dicho porque es lo primero que uno sospecha.
        //
        // **Importa más de lo que parece:** ningún flujo de CI compila Android
        // —`flutter_ci.yml` hace `pub get`, `analyze` y `test`; el de E2E compila
        // *web*—, y en este equipo no hay JDK 17+ (el del PATH es un JRE 8), así
        // que Gradle no puede correr: esto no saldría en verde ni en rojo, saldría
        // la primera vez que alguien construya el APK a mano. Se deja atado aquí.
        minSdk = maxOf(flutter.minSdkVersion, 23)
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
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
