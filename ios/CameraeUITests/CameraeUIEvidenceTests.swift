import XCTest

final class CameraeUIEvidenceTests: XCTestCase {
    private var outputDirectory: URL!
    private var capturedScreens: [EvidenceScreen] = []

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait

        let configuration = try loadConfiguration()
        guard !configuration.outputDirectory.isEmpty else {
            throw XCTSkip("CAMERAE_UI_EVIDENCE_DIR is only configured by generate-ui-evidence.sh")
        }

        outputDirectory = URL(fileURLWithPath: configuration.outputDirectory, isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
    }

    func testGenerateReleaseEvidence() throws {
        let app = launchCleanApplication()

        try capture("01-home", title: "Início", app: app)

        openWorkflow("Repeatable", app: app)
        XCTAssertTrue(app.buttons["Novo projeto Repeatable"].waitForExistence(timeout: 8))
        try capture("02-repeatable-projetos", title: "Repeatable · Projetos", app: app)

        app.buttons["Novo projeto Repeatable"].tap()
        XCTAssertTrue(app.staticTexts["Novo projeto Repeatable"].waitForExistence(timeout: 5))
        try capture("03-repeatable-novo-projeto", title: "Repeatable · Novo projeto", app: app)
        createProject(named: "Evidência Repeatable", app: app)

        XCTAssertTrue(app.buttons["Timelapse"].waitForExistence(timeout: 10))
        try capture("04-repeatable-configuracao-timelapse", title: "Repeatable · Configuração Timelapse", app: app)

        app.buttons["Vídeo"].tap()
        XCTAssertTrue(app.staticTexts["VÍDEO"].waitForExistence(timeout: 5))
        try capture("05-repeatable-configuracao-video", title: "Repeatable · Configuração Vídeo", app: app)

        app.buttons["Capturas"].tap()
        XCTAssertTrue(app.staticTexts["Nenhuma captura ainda"].waitForExistence(timeout: 5))
        try capture("06-repeatable-capturas", title: "Repeatable · Capturas", app: app)

        relaunch(app)
        openWorkflow("Astrophotography", app: app)
        XCTAssertTrue(app.buttons["Novo projeto Astro"].waitForExistence(timeout: 8))
        try capture("07-astro-projetos", title: "Astro · Projetos", app: app)

        app.buttons["Novo projeto Astro"].tap()
        XCTAssertTrue(app.staticTexts["Novo projeto Astro"].waitForExistence(timeout: 5))
        try capture("08-astro-novo-projeto", title: "Astro · Novo projeto", app: app)
        createProject(named: "Evidência Astro", app: app)

        XCTAssertTrue(app.buttons["Manual"].waitForExistence(timeout: 10))
        try capture("09-astro-configuracao", title: "Astro · Configuração", app: app)

        relaunch(app)
        openWorkflow("Edit", app: app)
        XCTAssertTrue(app.navigationBars["Editor"].waitForExistence(timeout: 8))
        try capture("10-editor-projetos", title: "Editor · Projetos", app: app)

        try writeManifestAndGallery()
    }

    private func launchCleanApplication() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(pt-BR)", "-AppleLocale", "pt_BR"]
        app.launch()
        XCTAssertTrue(app.buttons["Abrir Repeatable"].waitForExistence(timeout: 10))
        return app
    }

    private func relaunch(_ app: XCUIApplication) {
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["Abrir Repeatable"].waitForExistence(timeout: 10))
    }

    private func openWorkflow(_ name: String, app: XCUIApplication) {
        let button = app.buttons["Abrir \(name)"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.tap()
    }

    private func createProject(named name: String, app: XCUIApplication) {
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(name)
        app.buttons["Criar projeto"].tap()
    }

    private func capture(_ filename: String, title: String, app: XCUIApplication) throws {
        XCTAssertEqual(app.state, .runningForeground)
        Thread.sleep(forTimeInterval: 0.35)

        let screenshot = XCUIScreen.main.screenshot()
        let fileURL = outputDirectory.appendingPathComponent(filename).appendingPathExtension("png")
        try screenshot.pngRepresentation.write(to: fileURL, options: .atomic)

        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = filename
        attachment.lifetime = .keepAlways
        add(attachment)
        capturedScreens.append(.init(filename: fileURL.lastPathComponent, title: title))
    }

    private func writeManifestAndGallery() throws {
        let release = try loadConfiguration().title
        let manifest = EvidenceManifest(
            title: release,
            generatedAt: ISO8601DateFormatter().string(from: Date()),
            device: ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? "iOS Simulator",
            screens: capturedScreens
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(
            to: outputDirectory.appendingPathComponent("manifest.json"),
            options: .atomic
        )

        let cards = capturedScreens.map { screen in
            "<figure><a href=\"\(screen.filename)\"><img src=\"\(screen.filename)\" alt=\"\(screen.title)\"></a><figcaption>\(screen.title)</figcaption></figure>"
        }.joined(separator: "\n")
        let html = """
        <!doctype html><html lang="pt-BR"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
        <title>\(release)</title><style>body{margin:0;background:#11131a;color:#f7f3ee;font:16px -apple-system,BlinkMacSystemFont,sans-serif}header{padding:32px;max-width:1400px;margin:auto}h1{margin:0 0 8px}p{color:#aeb5c8}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(260px,1fr));gap:24px;padding:0 32px 40px;max-width:1400px;margin:auto}figure{margin:0;background:#1b1f2a;border:1px solid #303747;border-radius:18px;overflow:hidden}img{width:100%;display:block;background:#000}figcaption{padding:14px 16px}</style></head>
        <body><header><h1>\(release)</h1><p>\(capturedScreens.count) telas · \(manifest.device) · \(manifest.generatedAt)</p></header><main class="grid">\(cards)</main></body></html>
        """
        try Data(html.utf8).write(to: outputDirectory.appendingPathComponent("index.html"), options: .atomic)
    }

    private func loadConfiguration() throws -> EvidenceConfiguration {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = repositoryRoot.appendingPathComponent(".build/ui-evidence/config.plist")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("UI evidence configuration is only created by generate-ui-evidence.sh")
        }
        return try PropertyListDecoder().decode(EvidenceConfiguration.self, from: Data(contentsOf: url))
    }
}

private struct EvidenceScreen: Codable {
    let filename: String
    let title: String
}

private struct EvidenceManifest: Codable {
    let title: String
    let generatedAt: String
    let device: String
    let screens: [EvidenceScreen]
}

private struct EvidenceConfiguration: Codable {
    let outputDirectory: String
    let title: String
}
