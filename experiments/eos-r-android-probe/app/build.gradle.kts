plugins {
    id("com.android.application")
}

android {
    namespace = "com.camerae.eosrprobe"
    compileSdk = 36

    buildFeatures {
        buildConfig = true
    }

    defaultConfig {
        applicationId = "com.camerae.eosrprobe"
        minSdk = 26
        targetSdk = 36
        versionCode = 12
        versionName = "0.5.2"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}
