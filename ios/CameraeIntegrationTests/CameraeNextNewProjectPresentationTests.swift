import Testing
@testable import Camerae

struct CameraeNextNewProjectPresentationTests {
    @Test func repeatableCreationUsesRepeatableThemeAndLanguage() {
        let presentation = CameraeNextNewProjectPresentation(module: .repeatable)

        #expect(presentation.title == "Novo projeto Repeatable")
        #expect(presentation.theme == .repeatable)
        #expect(presentation.systemImage == "repeat")
    }

    @Test func astroAndEditorKeepTheirOwnIdentity() {
        #expect(CameraeNextNewProjectPresentation(module: .astrophotography).theme == .astro)
        #expect(CameraeNextNewProjectPresentation(module: .edit).theme == .editor)
    }

    @Test func ipadCreationSheetHasEnoughHeightForThePrimaryAction() {
        let phone = CameraeNextNewProjectLayout(isPad: false)
        let pad = CameraeNextNewProjectLayout(isPad: true)

        #expect(phone.preferredSheetHeight == nil)
        #expect(pad.preferredSheetHeight == 620)
        #expect(pad.contentMaxWidth == 420)
    }
}
