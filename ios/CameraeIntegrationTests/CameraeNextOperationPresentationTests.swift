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
