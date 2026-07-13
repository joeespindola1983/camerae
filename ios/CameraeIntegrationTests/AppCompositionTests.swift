import Foundation
import Testing
@testable import Camerae

@Suite("App component integration", .serialized)
@MainActor
struct AppCompositionTests {
    @Test("ProjectStore composes with the real catalog and persists across instances")
    func projectStoreComposition() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CameraeIntegrationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let firstStore = ProjectStore(rootDirectory: root)
        let created = try await firstStore.createProject(module: .repeatable, name: "Integrated")
        let secondStore = ProjectStore(rootDirectory: root)
        await secondStore.reloadNow()

        #expect(created.name == "Integrated")
        #expect(secondStore.projects.map(\.id) == [created.id])
        #expect(secondStore.projects.first?.summary == .empty)
    }
}
