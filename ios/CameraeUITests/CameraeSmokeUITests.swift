import XCTest

final class CameraeSmokeUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testHomeExposesIndependentModuleActions() {
        let app = XCUIApplication()
        app.launchArguments.append("-ui-testing")
        app.launch()

        XCTAssertTrue(app.images["Camerae"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Criar projeto Repeatable"].exists)
        XCTAssertTrue(app.buttons["Projetos Repeatable, 0"].exists || app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Projetos Repeatable'" )).firstMatch.exists)
        XCTAssertTrue(app.buttons["Criar projeto Astrophotography"].exists)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Projetos Astrophotography'" )).firstMatch.exists)
    }
}
