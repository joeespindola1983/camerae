import Testing
@testable import Camerae

struct CameraeNextSegmentedControlTests {
    @Test func selectionStateMovesWithTheBoundValue() {
        let items = [
            CameraeNextSegmentItem(value: 15, label: "15 min"),
            CameraeNextSegmentItem(value: 30, label: "30 min"),
            CameraeNextSegmentItem(value: 60, label: "1 h")
        ]

        #expect(CameraeNextSegmentedControlModel(items: items, selection: 30).selectedIndex == 1)
        #expect(CameraeNextSegmentedControlModel(items: items, selection: 60).selectedIndex == 2)
    }

    @Test func workflowModeUsesSemanticValuesInsteadOfIndexes() {
        #expect(CameraeNextCaptureModeOption.repeatableItems.map(\.value) == [.video, .timelapse])
        #expect(CameraeNextCaptureModeOption.astroItems.map(\.value) == [.automatic, .manual])
    }
}
