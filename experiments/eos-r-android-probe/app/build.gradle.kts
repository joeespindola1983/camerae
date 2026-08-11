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
        versionCode = 8
        versionName = "0.4.3"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}
