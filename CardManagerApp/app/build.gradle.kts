plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.serialization")
}

// رقم البناء من CI (GITHUB_RUN_NUMBER) — يجعل كل نسخة **تحديثاً** فوق سابقتها
// عند التثبيت بدل رقمٍ ثابت. محلياً يسقط إلى 1.
val ciBuildNumber = (System.getenv("GITHUB_RUN_NUMBER")?.toIntOrNull() ?: 1)

android {
    namespace = "com.binwaps.cardmanager"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.binwaps.cardmanager"
        minSdk = 26
        targetSdk = 34
        versionCode = ciBuildNumber
        versionName = "3.$ciBuildNumber"
        vectorDrawables { useSupportLibrary = true }
    }

    // مفتاح توقيع **ثابت** داخل المستودع: بدونه كان كل بناء CI يوقّع بمفتاح
    // عشوائي جديد فيرفض أندرويد تثبيت التحديث فوق النسخة المثبّتة (توقيع
    // مختلف) — فيبقى المستخدم على نسخة قديمة ويظن أن الأعطال لم تُصلح.
    // المفتاح للتوزيع الجانبي (خارج المتاجر) فوجوده في المستودع مقبول.
    signingConfigs {
        create("shared") {
            storeFile = file("signing/shared.keystore")
            storePassword = "cardmanager2026"
            keyAlias = "cardmanager"
            keyPassword = "cardmanager2026"
        }
    }

    buildTypes {
        debug {
            signingConfig = signingConfigs.getByName("shared")
        }
        release {
            isMinifyEnabled = false
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            signingConfig = signingConfigs.getByName("shared")
        }
    }

    // تطبيقان من نفس الكود: تطبيق المشترك، وتطبيق الأدمن لإصدار التراخيص
    flavorDimensions += "audience"
    productFlavors {
        create("subscriber") {
            dimension = "audience"
            applicationId = "com.binwaps.cardmanager"
            resValue("string", "app_name", "مدير الكروت")
        }
        create("admin") {
            dimension = "audience"
            applicationId = "com.binwaps.cardmanager.admin"
            versionNameSuffix = "-admin"
            resValue("string", "app_name", "لوحة التراخيص")
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
    buildFeatures {
        compose = true
        buildConfig = true
    }
    composeOptions { kotlinCompilerExtensionVersion = "1.5.8" }
    packaging {
        resources { excludes += "/META-INF/{AL2.0,LGPL2.1}" }
    }
}

dependencies {
    // اختبارات وحدة تعمل على JVM في كل بناء — تمنع رجوع الأعطال المتكررة
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.jetbrains.kotlin:kotlin-test-junit:1.9.22")

    val composeBom = platform("androidx.compose:compose-bom:2024.02.00")
    implementation(composeBom)
    implementation("androidx.core:core-ktx:1.12.0")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.7.0")
    implementation("androidx.activity:activity-compose:1.8.2")
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-graphics")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.navigation:navigation-compose:2.7.7")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.6.2")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")
    // QR code generation
    implementation("com.google.zxing:core:3.5.2")
    // Bluetooth ESC/POS thermal printing
    implementation("com.github.DantSu:ESCPOS-ThermalPrinter-Android:3.3.0")
    // MikroTik RouterOS API client
    implementation("me.legrange:mikrotik:3.0.7")
    // Image loading for template backgrounds
    implementation("io.coil-kt:coil-compose:2.5.0")
    // Firebase — المزامنة الحية والدردشة بين الأدمن والمشتركين (تهيئة يدوية بلا google-services)
    implementation(platform("com.google.firebase:firebase-bom:32.7.4"))
    implementation("com.google.firebase:firebase-firestore-ktx")
    implementation("com.google.firebase:firebase-auth-ktx")
}
