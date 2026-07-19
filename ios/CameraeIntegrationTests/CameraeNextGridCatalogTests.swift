import Testing
@testable import Camerae

@Suite("Camerae Next photographic grids")
struct CameraeNextGridCatalogTests {
    @Test("catalog includes the principal photographic composition grids")
    func completeCatalog() {
        #expect(CameraeNextGridStyle.allCases.map(\.title) == [
            "Regra dos terços",
            "Proporção áurea",
            "Espiral áurea",
            "Espiral áurea invertida",
            "Diagonais",
            "Triângulos",
            "Grade 4 × 4",
            "Centro e cruz"
        ])
    }

    @Test("spiral variants share one renderer through mirroring")
    func spiralMirroring() {
        #expect(CameraeNextGridStyle.goldenSpiral.usesGoldenSpiral)
        #expect(!CameraeNextGridStyle.goldenSpiral.isMirrored)
        #expect(CameraeNextGridStyle.goldenSpiralMirrored.usesGoldenSpiral)
        #expect(CameraeNextGridStyle.goldenSpiralMirrored.isMirrored)
    }

    @Test("default grid remains the familiar rule of thirds")
    func defaultGrid() {
        #expect(CameraeNextGridStyle.default == .ruleOfThirds)
    }
}
