import CameraeCore
import XCTest

final class ProjectCatalogPerformanceTests: XCTestCase {
    func testWarmIndexLoadForTwoHundredProjects() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CameraePerformanceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let prepared = expectation(description: "fixture prepared")
        Task {
            let catalog = ProjectCatalog(rootDirectory: root)
            for index in 0..<200 {
                _ = try await catalog.createProject(module: .repeatable, name: "Project \(index)")
            }
            prepared.fulfill()
        }
        wait(for: [prepared], timeout: 30)

        measure(metrics: [XCTClockMetric(), XCTMemoryMetric(), XCTStorageMetric()]) {
            let loaded = expectation(description: "warm index loaded")
            Task {
                let snapshot = try await ProjectCatalog(rootDirectory: root).load()
                XCTAssertEqual(snapshot.projects.count, 200)
                loaded.fulfill()
            }
            wait(for: [loaded], timeout: 5)
        }
    }
}
