import XCTest

final class CameraeSmokeUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testHomeExposesIndependentModuleActions() {
        let app = XCUIApplication()
        app.launchArguments.append("-ui-testing")
        XCUIDevice.shared.orientation = .portrait
        app.launch()

        XCTAssertTrue(app.images["Camerae"].waitForExistence(timeout: 5))
        let repeatableCreate = app.buttons["Criar projeto Repeatable"]
        let repeatableProjects = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Projetos Repeatable'" )).firstMatch
        let astroCreate = app.buttons["Criar projeto Astrophotography"]
        let astroProjects = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Projetos Astrophotography'" )).firstMatch
        let editCreate = app.buttons["Criar projeto Edit"]
        let editProjects = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Projetos Edit'" )).firstMatch

        XCTAssertTrue(repeatableCreate.exists)
        XCTAssertTrue(repeatableProjects.exists)
        XCTAssertTrue(astroCreate.exists)
        XCTAssertTrue(astroProjects.exists)
        XCTAssertTrue(editCreate.exists)
        XCTAssertTrue(editProjects.exists)

        XCTAssertEqual(repeatableCreate.frame.midY, astroCreate.frame.midY, accuracy: 2)
        XCTAssertEqual(repeatableProjects.frame.midY, astroProjects.frame.midY, accuracy: 2)
        XCTAssertLessThan(repeatableCreate.frame.midX, astroCreate.frame.midX)
        XCTAssertGreaterThan(editCreate.frame.midY, repeatableCreate.frame.midY)
    }
}
