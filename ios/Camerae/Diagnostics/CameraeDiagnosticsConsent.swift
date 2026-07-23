import FirebaseAnalytics

struct CameraeDiagnosticsConsentState: Equatable, Sendable {
    let crashlyticsEnabled: Bool
    let analyticsEnabled: Bool
}

@MainActor
protocol CameraeDiagnosticsConsentBackend: AnyObject {
    func setCrashlyticsCollectionEnabled(_ enabled: Bool)
    func setAnalyticsCollectionEnabled(_ enabled: Bool)
}

@MainActor
final class FirebaseDiagnosticsConsentBackend: CameraeDiagnosticsConsentBackend {
    func setCrashlyticsCollectionEnabled(_ enabled: Bool) {
        CameraeCrashReporter.shared.setCollectionEnabled(enabled)
    }

    func setAnalyticsCollectionEnabled(_ enabled: Bool) {
        Analytics.setAnalyticsCollectionEnabled(enabled)
    }
}

@MainActor
final class CameraeDiagnosticsConsent {
    static let shared = CameraeDiagnosticsConsent()

    private let backend: CameraeDiagnosticsConsentBackend
    private var isCollectionAllowed: Bool

    init(
        backend: CameraeDiagnosticsConsentBackend? = nil,
        isCollectionAllowed: Bool = true
    ) {
        self.backend = backend ?? FirebaseDiagnosticsConsentBackend()
        self.isCollectionAllowed = isCollectionAllowed
    }

    func configure(isCollectionAllowed: Bool) {
        self.isCollectionAllowed = isCollectionAllowed
    }

    func apply(_ state: CameraeDiagnosticsConsentState) {
        backend.setCrashlyticsCollectionEnabled(isCollectionAllowed && state.crashlyticsEnabled)
        backend.setAnalyticsCollectionEnabled(isCollectionAllowed && state.analyticsEnabled)
    }

    func apply(settings: CameraeSettingsStore) {
        apply(.init(
            crashlyticsEnabled: settings.effectiveCrashCollectionEnabled,
            analyticsEnabled: settings.effectiveAnalyticsCollectionEnabled
        ))
    }
}
