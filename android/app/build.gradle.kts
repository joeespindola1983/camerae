plugins {
    id("com.android.application")
}

android {
    namespace = "com.camerae.android"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.camerae.android"
        minSdk = 26
        targetSdk = 35
        versionCode = 1
        versionName = "0.1.0"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

dependencies {
    implementation("org.opencv:opencv:4.10.0")
}
