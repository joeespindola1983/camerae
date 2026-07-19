import CameraeCore
import Testing
@testable import Camerae

struct CameraeNextEditExportPresentationTests {
    @Test func describesPortraitAndLandscapeOutput() {
        #expect(CameraeNextEditExportPresentation(canvas: .portrait9x16, clipCount: 3, duration: 65, usesAlignment: true).resolution == "1080 × 1920")
        #expect(CameraeNextEditExportPresentation(canvas: .landscape16x9, clipCount: 3, duration: 65, usesAlignment: false).resolution == "1920 × 1080")
    }

    @Test func formatsDurationAndAlignmentWithoutDependingOnTheView() {
        let presentation = CameraeNextEditExportPresentation(
            canvas: .landscape16x9,
            clipCount: 4,
            duration: 125,
            usesAlignment: true
        )

        #expect(presentation.duration == "02:05")
        #expect(presentation.clipCount == "4")
        #expect(presentation.alignment == "Aplicado")
    }
}
