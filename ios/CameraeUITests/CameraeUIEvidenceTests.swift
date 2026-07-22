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

        openWorkflow(.repeatable, app: app)
        try capture("02-repeatable-projetos", title: "Repeatable · Projetos", app: app)

        openNewProject(app: app)
        try capture("03-repeatable-novo-projeto", title: "Repeatable · Novo projeto", app: app)
        createProject(app: app)

        try capture("04-repeatable-configuracao-timelapse", title: "Repeatable · Configuração Timelapse", app: app)

        element(localizedTitle(ptBR: "Vídeo", es: "Vídeo", en: "Video", fr: "Vidéo", de: "Video", ru: "Видео"), app: app).tap()
        try capture("05-repeatable-configuracao-video", title: "Repeatable · Configuração Vídeo", app: app)

        element(localizedTitle(ptBR: "Capturas", es: "Capturas", en: "Captures", fr: "Captures", de: "Aufnahmen", ru: "Съёмки"), app: app).tap()
        try capture("06-repeatable-capturas", title: "Repeatable · Capturas", app: app)

        relaunch(app)
        openWorkflow(.astrophotography, app: app)
        try capture("07-astro-projetos", title: "Astro · Projetos", app: app)

        openNewProject(app: app)
        try capture("08-astro-novo-projeto", title: "Astro · Novo projeto", app: app)
        createProject(app: app)

        try capture("09-astro-configuracao", title: "Astro · Configuração", app: app)

        relaunch(app)
        openWorkflow(.edit, app: app)
        try capture("10-editor-projetos", title: "Editor · Projetos", app: app)

        try writeManifestAndGallery()
    }

    private func launchCleanApplication() -> XCUIApplication {
        let configuration = try! loadConfiguration()
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing",
            "-AppleLanguages", "(\(configuration.localeIdentifier))",
            "-AppleLocale", configuration.appleLocale
        ]
        app.launch()
        XCTAssertTrue(element("camerae.module.repeatable.open", app: app).waitForExistence(timeout: 10))
        return app
    }

    private func relaunch(_ app: XCUIApplication) {
        app.terminate()
        app.launch()
        XCTAssertTrue(element("camerae.module.repeatable.open", app: app).waitForExistence(timeout: 10))
    }

    private func openWorkflow(_ workflow: EvidenceWorkflow, app: XCUIApplication) {
        let button = element("camerae.module.\(workflow.rawValue).open", app: app)
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    private func createProject(app: XCUIApplication) {
        let stableElement = element("camerae.project.create", app: app)
        if stableElement.waitForExistence(timeout: 8) {
            stableElement.tap()
        } else {
            element(createProjectTitle(), app: app).tap()
        }
    }

    private func element(_ identifier: String, app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func openNewProject(app: XCUIApplication) {
        let button = element("camerae.project.empty.create", app: app)
        XCTAssertTrue(button.waitForExistence(timeout: 8))
        button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    private func createProjectTitle() -> String {
        let locale = try! loadConfiguration().localeIdentifier
        return [
            "pt-BR": "Criar projeto",
            "es": "Crear proyecto",
            "en": "Create project",
            "fr": "Créer le projet",
            "de": "Projekt erstellen",
            "ru": "Создать проект"
        ][locale] ?? "Criar projeto"
    }

    private func localizedTitle(ptBR: String, es: String, en: String, fr: String, de: String, ru: String) -> String {
        let locale = try! loadConfiguration().localeIdentifier
        return ["pt-BR": ptBR, "es": es, "en": en, "fr": fr, "de": de, "ru": ru][locale] ?? ptBR
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
            locale: try loadConfiguration().localeIdentifier,
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
        <!doctype html><html lang="\(manifest.locale)"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
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
    let locale: String
    let screens: [EvidenceScreen]
}

private struct EvidenceConfiguration: Codable {
    let outputDirectory: String
    let title: String
    let localeIdentifier: String
    let appleLocale: String
}

private enum EvidenceWorkflow: String {
    case repeatable
    case astrophotography
    case edit
}
