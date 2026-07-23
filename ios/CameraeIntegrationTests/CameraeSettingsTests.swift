import CameraeCore
import Foundation
import Testing
@testable import Camerae

@Suite("Camerae settings")
@MainActor
struct CameraeSettingsTests {
    @Test("new installs use the approved capture and privacy defaults")
    func defaults() {
        let defaults = isolatedDefaults()
        let settings = CameraeSettingsStore(defaults: defaults)

        #expect(settings.diagnosticsEnabled)
        #expect(settings.analyticsEnabled)
        #expect(settings.repeatableFormat == .heic)
        #expect(settings.astroFormat == .dng)
        #expect(settings.performanceMode == .automatic)
        #expect(settings.preserveOriginals)
        #expect(settings.lowStorageWarningEnabled)
    }

    @Test("privacy opt-out disables both Firebase collection paths")
    func privacyOptOut() {
        let defaults = isolatedDefaults()
        let settings = CameraeSettingsStore(defaults: defaults)

        settings.diagnosticsEnabled = false

        #expect(!settings.effectiveCrashCollectionEnabled)
        #expect(!settings.effectiveAnalyticsCollectionEnabled)
    }

    @Test("settings survive recreation and feed new project configuration")
    func persistenceAndConfiguration() {
        let defaults = isolatedDefaults()
        let settings = CameraeSettingsStore(defaults: defaults)
        settings.repeatableFormat = .jpeg
        settings.astroFormat = .heic
        settings.performanceMode = .maximumQuality

        let restored = CameraeSettingsStore(defaults: defaults)

        #expect(restored.repeatableFormat == .jpeg)
        #expect(restored.astroFormat == .heic)
        #expect(restored.performanceMode == .maximumQuality)
        #expect(restored.defaultSourceFormat(for: .repeatable) == .jpeg)
        #expect(restored.defaultSourceFormat(for: .astrophotography) == .heic)
    }

    private func isolatedDefaults() -> UserDefaults {
        let suite = "CameraeSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}
