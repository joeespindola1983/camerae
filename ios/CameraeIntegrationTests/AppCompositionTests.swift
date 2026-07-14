import Foundation
import Testing
@testable import Camerae

@Suite("App component integration", .serialized)
@MainActor
struct AppCompositionTests {
    @Test("ProjectStore composes with the real catalog and persists across instances")
    func projectStoreComposition() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CameraeIntegrationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let firstStore = ProjectStore(rootDirectory: root)
        let created = try await firstStore.createProject(module: .repeatable, name: "Integrated")
        let secondStore = ProjectStore(rootDirectory: root)
        await secondStore.reloadNow()

        #expect(created.name == "Integrated")
        #expect(secondStore.projects.map(\.id) == [created.id])
        #expect(secondStore.projects.first?.summary == .empty)
    }

    @Test("session cards describe image sequences and compilation state")
    func sessionCardMetadataForSequence() {
        let summary = makeSummary(kind: .timelapse, frames: 240, hasVideo: false)
        let metadata = SessionCardMetadata(summary: summary, duration: 95)

        #expect(metadata.title == "Timelapse")
        #expect(metadata.mediaDescription == "Sequência de imagens")
        #expect(metadata.frameDescription == "240 frames")
        #expect(metadata.durationDescription == "01:35")
        #expect(metadata.compilationDescription == "Aguardando compilação")
    }

    @Test("session cards distinguish ready video output")
    func sessionCardMetadataForCompiledVideo() {
        let summary = makeSummary(kind: .video, frames: 1, hasVideo: true)
        let metadata = SessionCardMetadata(summary: summary, duration: 7)

        #expect(metadata.mediaDescription == "Vídeo")
        #expect(metadata.compilationDescription == "Vídeo pronto")
    }

    @Test("magnifier stays fully visible while dragging")
    func magnifierClampsToDisplayBounds() {
        let geometry = AlignmentMagnifierGeometry(
            displaySize: CGSize(width: 390, height: 844),
            lensSize: 140,
            margin: 8
        )

        #expect(geometry.clampedCenter(CGPoint(x: -40, y: 900)) == CGPoint(x: 78, y: 766))
        #expect(geometry.clampedCenter(CGPoint(x: 220, y: 300)) == CGPoint(x: 220, y: 300))
    }

    @Test("magnifier aligns the sampled point with its local center")
    func magnifierContentOffset() {
        let geometry = AlignmentMagnifierGeometry(
            displaySize: CGSize(width: 390, height: 844),
            lensSize: 140,
            margin: 8
        )

        #expect(geometry.contentOffset(samplePoint: CGPoint(x: 300, y: 200), zoom: 4) == CGSize(width: -1_130, height: -730))
    }

    @Test("magnifier zoom cycles through the supported levels")
    func magnifierZoomCycle() {
        #expect(AlignmentMagnifierZoom.two.next == .four)
        #expect(AlignmentMagnifierZoom.four.next == .six)
        #expect(AlignmentMagnifierZoom.six.next == .two)
    }

    private func makeSummary(
        kind: RepeatableCaptureKind,
        frames: Int,
        hasVideo: Bool
    ) -> TimelapseSessionSummary {
        let directory = FileManager.default.temporaryDirectory
        let session = TimelapseSession(
            id: UUID(),
            projectID: UUID(),
            module: .repeatable,
            captureKind: kind,
            referenceMotion: nil,
            referenceGeoPose: nil,
            referenceOrientation: nil,
            cameraLens: nil,
            name: "session_test",
            directoryURL: directory,
            createdAt: Date(timeIntervalSince1970: 0)
        )
        return TimelapseSessionSummary(
            session: session,
            captureKind: kind,
            frameCount: frames,
            captureDuration: 95,
            referenceFrameURL: nil,
            videoURL: kind == .timelapse && hasVideo ? directory.appendingPathComponent("timelapse.mp4") : nil,
            videoClipURL: kind == .video && hasVideo ? directory.appendingPathComponent("video.mov") : nil,
            isAstroProcessed: false,
            hasRenderedOutput: hasVideo
        )
    }
}
