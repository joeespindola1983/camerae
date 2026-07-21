import Foundation
import Testing
@testable import Camerae

@Suite("Camerae Next Repeatable alignment flow")
struct CameraeNextRepeatableAlignmentFlowTests {
    @Test("Timelapse alignment defaults match the approved Figma screen")
    func timelapseDefaults() {
        let settings = CameraeNextRepeatableAlignmentSettings.timelapseDefault
        let presentation = CameraeNextRepeatableAlignmentSetupPresentation(
            captureKind: .timelapse,
            settings: settings
        )

        #expect(settings.isEnabled)
        #expect(settings.model == .automatic)
        #expect(settings.maximumCropFraction == 0.20)
        #expect(settings.videoScope == .constantReframe)
        #expect(presentation.navigationTitle == "Alinhamento do timelapse")
        #expect(presentation.headline == "Corrigir antes de gerar o vídeo")
        #expect(presentation.availableModels == [.position, .automatic])
        #expect(presentation.unavailableModel == .perspectiveAndDeformation)
        #expect(!presentation.showsVideoScope)
    }

    @Test("Video alignment exposes only constant reframe")
    func videoScope() {
        let presentation = CameraeNextRepeatableAlignmentSetupPresentation(
            captureKind: .video,
            settings: .videoDefault
        )

        #expect(presentation.navigationTitle == "Alinhamento do vídeo")
        #expect(presentation.headline == "Corrigir o enquadramento do vídeo")
        #expect(presentation.showsVideoScope)
        #expect(presentation.availableVideoScopes == [.constantReframe])
        #expect(presentation.unavailableVideoScope == .temporalStabilization)
    }

    @Test("Alignment settings survive a project round trip")
    func persistenceRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        var settings = CameraeNextRepeatableAlignmentSettings.timelapseDefault
        settings.model = .position
        let store = CameraeNextRepeatableAlignmentSettingsStore(projectDirectoryURL: directory)

        try store.save(settings, for: .timelapse)

        #expect(try store.load(for: .timelapse) == settings)
        #expect(try store.load(for: .video) == .videoDefault)
    }

    @Test("Review and processing presentations are deterministic")
    func resultPresentations() {
        let review = CameraeNextRepeatableAlignmentReviewPresentation(
            totalFrames: 128,
            appliedFrames: 126,
            reviewFrames: 2,
            confidence: 0.94,
            cropFraction: 0.06
        )
        #expect(review.readyLabel == "PRONTO · 128 FRAMES")
        #expect(review.confidenceLabel == "CONFIANÇA 94% · 126 APLICADOS · 2 REVISÃO")
        #expect(review.cropLabel == "Crop estimado: 6%")

        let progress = CameraeNextRepeatableAlignmentProgressPresentation(
            stage: .correctingFrames,
            completedFrames: 82,
            totalFrames: 128,
            remainingSeconds: 14
        )
        #expect(progress.stageLabel == "ETAPA 2 DE 3")
        #expect(progress.title == "Corrigindo quadros")
        #expect(progress.percentageLabel == "64%")
        #expect(progress.detailLabel == "82 / 128 FRAMES · 00:14 RESTANTE")
    }
}
