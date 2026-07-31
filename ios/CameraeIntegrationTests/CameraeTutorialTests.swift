import Foundation
import Testing
@testable import Camerae

@Suite("Camerae video tutorials")
struct CameraeTutorialTests {
    @Test("a tutorial is presented once for its current content version")
    func firstUsePresentation() throws {
        let defaults = try #require(UserDefaults(suiteName: #function))
        defer { defaults.removePersistentDomain(forName: #function) }
        let store = CameraeTutorialProgressStore(defaults: defaults)
        let tutorial = CameraeTutorial.spatialMapping

        #expect(store.shouldPresent(tutorial))

        store.markCompleted(tutorial)

        #expect(!store.shouldPresent(tutorial))
    }

    @Test("a newer tutorial content version is presented again")
    func contentVersionPresentation() throws {
        let defaults = try #require(UserDefaults(suiteName: #function))
        defer { defaults.removePersistentDomain(forName: #function) }
        let store = CameraeTutorialProgressStore(defaults: defaults)
        let original = CameraeTutorial(
            id: .spatialMapping,
            contentVersion: 1,
            title: "Original",
            detail: "Original",
            videoResourceName: "original",
            fallbackSteps: ["Original"]
        )
        let revised = CameraeTutorial(
            id: .spatialMapping,
            contentVersion: 2,
            title: "Revisado",
            detail: "Revisado",
            videoResourceName: "revisado",
            fallbackSteps: ["Revisado"]
        )

        store.markCompleted(original)

        #expect(store.shouldPresent(revised))
    }

    @Test("help can reopen a completed tutorial without resetting first-use progress")
    func helpReopensCompletedTutorial() throws {
        let defaults = try #require(UserDefaults(suiteName: #function))
        defer { defaults.removePersistentDomain(forName: #function) }
        let store = CameraeTutorialProgressStore(defaults: defaults)
        let tutorial = CameraeTutorial.spatialMapping
        store.markCompleted(tutorial)

        #expect(
            CameraeTutorialPresentationPolicy.route(
                for: .help,
                tutorial: tutorial,
                progressStore: store
            ) == .present
        )
        #expect(!store.shouldPresent(tutorial))
    }

    @Test("first use continues directly after completion but presents before completion")
    func firstUseRoute() throws {
        let defaults = try #require(UserDefaults(suiteName: #function))
        defer { defaults.removePersistentDomain(forName: #function) }
        let store = CameraeTutorialProgressStore(defaults: defaults)
        let tutorial = CameraeTutorial.spatialMapping

        #expect(
            CameraeTutorialPresentationPolicy.route(
                for: .firstUse,
                tutorial: tutorial,
                progressStore: store
            ) == .present
        )

        store.markCompleted(tutorial)

        #expect(
            CameraeTutorialPresentationPolicy.route(
                for: .firstUse,
                tutorial: tutorial,
                progressStore: store
            ) == .continueToFeature
        )
    }

    @Test("missing media exposes instructions and a safe continuation")
    func unavailableMediaCapabilities() {
        #expect(
            CameraeTutorialCapabilityPolicy.actions(for: .unavailable) ==
                [.readFallback, .continueToFeature, .close]
        )
        #expect(!CameraeTutorial.spatialMapping.fallbackSteps.isEmpty)
    }
}
