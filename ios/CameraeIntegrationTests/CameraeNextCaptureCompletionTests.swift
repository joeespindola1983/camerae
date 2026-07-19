import Testing
@testable import Camerae

@Suite("Camerae Next capture completion")
struct CameraeNextCaptureCompletionTests {
    @Test("Repeatable completion returns to its project without processing")
    func repeatableCompletion() {
        let presentation = CameraeNextCaptureCompletionPresentation(module: .repeatable)

        #expect(presentation.title == "Captura concluída")
        #expect(presentation.primaryActionTitle == "Voltar ao projeto")
        #expect(!presentation.offersProcessing)
        #expect(presentation.accentTheme == .repeatable)
    }

    @Test("Astro completion continues into image processing")
    func astroCompletion() {
        let presentation = CameraeNextCaptureCompletionPresentation(module: .astrophotography)

        #expect(presentation.title == "Sessão concluída")
        #expect(presentation.primaryActionTitle == "Processar imagens")
        #expect(presentation.offersProcessing)
        #expect(presentation.accentTheme == .astro)
    }
}
