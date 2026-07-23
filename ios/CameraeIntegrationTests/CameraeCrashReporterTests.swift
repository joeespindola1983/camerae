import Testing
@testable import Camerae

struct CameraeCrashReporterTests {
    @Test func configurationReadsReleasePolicyWithoutAssumingCollection() {
        #expect(
            CameraeCrashReportingConfiguration(infoDictionary: [:])
                == .init(isEnabled: false, releaseChannel: "unknown")
        )
        #expect(
            CameraeCrashReportingConfiguration(infoDictionary: [
                "CameraeCrashlyticsCollectionEnabled": "YES",
                "CameraeReleaseChannel": "qa"
            ])
                == .init(isEnabled: true, releaseChannel: "qa")
        )
    }

    @Test func disabledReportingDoesNotAttachContextOrLogs() {
        let backend = CrashReportingBackendSpy()
        let reporter = CameraeCrashReporter(backend: backend)

        reporter.start(
            configuration: .init(isEnabled: false, releaseChannel: "debug"),
            appVersion: "8.4.0",
            build: "22"
        )

        #expect(backend.collectionStates == [false])
        #expect(backend.values.isEmpty)
        #expect(backend.logs.isEmpty)
    }

    @Test func enabledReportingUsesOnlyAllowlistedNonPersonalContext() {
        let backend = CrashReportingBackendSpy()
        let reporter = CameraeCrashReporter(backend: backend)

        reporter.start(
            configuration: .init(isEnabled: true, releaseChannel: "qa"),
            appVersion: "8.4.0",
            build: "22"
        )
        reporter.setModule(.repeatable)

        #expect(backend.collectionStates == [true])
        #expect(backend.values == [
            "app_version": "8.4.0",
            "app_build": "22",
            "release_channel": "qa",
            "diagnostic_module": "repeatable"
        ])
        #expect(backend.logs == ["camerae_started"])
    }

    @Test func appModulesMapToFiniteDiagnosticValues() {
        #expect(CameraeDiagnosticModule(module: .repeatable) == .repeatable)
        #expect(CameraeDiagnosticModule(module: .astrophotography) == .astro)
        #expect(CameraeDiagnosticModule(module: .edit) == .edit)
    }
}

private final class CrashReportingBackendSpy: CameraeCrashReportingBackend {
    private(set) var collectionStates: [Bool] = []
    private(set) var values: [String: String] = [:]
    private(set) var logs: [String] = []

    func setCollectionEnabled(_ enabled: Bool) {
        collectionStates.append(enabled)
    }

    func setValue(_ value: String, forKey key: String) {
        values[key] = value
    }

    func log(_ message: String) {
        logs.append(message)
    }
}
