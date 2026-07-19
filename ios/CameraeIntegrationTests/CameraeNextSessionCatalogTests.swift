import Foundation
import Testing
@testable import Camerae

struct CameraeNextSessionCatalogTests {
    @Test func catalogHidesEmptyCaptureShells() {
        let summaries = [fixture(frameCount: 0), fixture(frameCount: 8)]
        let catalog = CameraeNextSessionCatalogModel(summaries: summaries)

        #expect(catalog.sessions.count == 1)
        #expect(catalog.totalFrames == 8)
    }

    @Test func summaryUsesModuleSpecificLanguage() {
        #expect(CameraeNextSessionCatalogPresentation(module: .repeatable).title == "Capturas Repeatable")
        #expect(CameraeNextSessionCatalogPresentation(module: .astrophotography).title == "Sessões Astro")
    }

    private func fixture(frameCount: Int) -> TimelapseSessionSummary {
        let session = TimelapseSession(
            id: UUID(),
            projectID: UUID(),
            module: .repeatable,
            captureKind: .timelapse,
            referenceMotion: nil,
            referenceGeoPose: nil,
            referenceOrientation: nil,
            cameraLens: nil,
            name: "Sessão",
            directoryURL: URL(fileURLWithPath: "/tmp/session"),
            createdAt: .now
        )
        return TimelapseSessionSummary(
            session: session,
            captureKind: .timelapse,
            frameCount: frameCount,
            captureDuration: nil,
            referenceFrameURL: nil,
            videoURL: nil,
            videoClipURL: nil,
            isAstroProcessed: false,
            hasRenderedOutput: false
        )
    }
}
