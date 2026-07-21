import Testing
@testable import Camerae

struct CameraeNextOperationPresentationTests {
    @Test func idleAndSuccessDoNotBlockInteraction() {
        #expect(!CameraeNextOperationPresentation(state: .idle).isBlocking)
        #expect(!CameraeNextOperationPresentation(state: .success("Concluído")).isBlocking)
    }

    @Test func processingIsBlockingAndCanExposeCancellation() {
        let presentation = CameraeNextOperationPresentation(
            state: .processing(title: "Processando", detail: "12 de 40", canCancel: true)
        )

        #expect(presentation.isBlocking)
        #expect(presentation.title == "Processando")
        #expect(presentation.detail == "12 de 40")
        #expect(presentation.canCancel)
    }

    @Test func failureIsVisibleWithoutPretendingToBeInProgress() {
        let presentation = CameraeNextOperationPresentation(state: .failure("Falha ao exportar"))

        #expect(!presentation.isBlocking)
        #expect(presentation.message == "Falha ao exportar")
        #expect(presentation.symbol == "exclamationmark.triangle")
    }
}

struct CameraeNextAstroProcessingPresentationTests {
    @Test func readyStateSummarizesFramesAndStartsInCreateArea() {
        let presentation = CameraeNextAstroProcessingPresentation(
            totalOriginalFrames: 132,
            activeOriginalFrames: 128,
            outputFrames: 384,
            stackingStartFrame: 18,
            stackSize: 10,
            videoSettings: .astroDefault,
            phase: .ready
        )

        #expect(presentation.selectedArea == .create)
        #expect(presentation.sourceCountText == "128 ativas • 4 ignoradas")
        #expect(presentation.stackingStartText == "Início automático • frame 18")
        #expect(presentation.primaryActionTitle == "Iniciar processo astro")
    }

    @Test func processingStateReportsStackingProgressWithoutPretendingVideoStarted() {
        let presentation = CameraeNextAstroProcessingPresentation(
            totalOriginalFrames: 128,
            activeOriginalFrames: 128,
            outputFrames: 384,
            stackingStartFrame: 1,
            stackSize: 10,
            videoSettings: .astroDefault,
            phase: .processing(currentStack: 24, totalStacks: 128, currentVideoFrame: 0, totalVideoFrames: 0)
        )

        #expect(presentation.processingStage == .stacking)
        #expect(presentation.processingDetail == "Stack 24/128")
        #expect(presentation.progressFraction == 0.1875)
    }

    @Test func completedStateMovesToVideoAndOffersThePlayer() {
        let presentation = CameraeNextAstroProcessingPresentation(
            totalOriginalFrames: 128,
            activeOriginalFrames: 128,
            outputFrames: 384,
            stackingStartFrame: 18,
            stackSize: 10,
            videoSettings: .astroDefault,
            phase: .completed(duration: 12.8)
        )

        #expect(presentation.selectedArea == .video)
        #expect(presentation.primaryActionTitle == "Abrir clipe astro")
        #expect(presentation.durationText == "12,8 s")
        #expect(presentation.resultMetrics.map(\.value) == ["12", "384", "12,8 s"])
    }
}
