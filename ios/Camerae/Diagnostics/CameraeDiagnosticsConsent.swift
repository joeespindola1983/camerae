import FirebaseAnalytics

@MainActor
final class CameraeDiagnosticsConsent {
    static let shared = CameraeDiagnosticsConsent()

    private init() {}

    func apply(settings: CameraeSettingsStore) {
        CameraeCrashReporter.shared.setCollectionEnabled(settings.effectiveCrashCollectionEnabled)
        Analytics.setAnalyticsCollectionEnabled(settings.effectiveAnalyticsCollectionEnabled)
    }
}
