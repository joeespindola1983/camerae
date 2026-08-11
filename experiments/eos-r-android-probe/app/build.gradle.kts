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
        versionCode = 7
        versionName = "0.4.2"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}
