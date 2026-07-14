import CameraeCore
import XCTest

final class MediaLibraryFilterPerformanceTests: XCTestCase {
    func testFilteringOneThousandMediaAssets() {
        let assets = (0..<1_000).map { index in
            MediaAssetDescriptor(
                reference: MediaAssetReference(
                    projectID: UUID(),
                    sessionID: UUID(),
                    kind: index.isMultiple(of: 2) ? .repeatableTimelapse : .astroTimelapse,
                    relativePath: "Sessions/\(index)/timelapse.mp4"
                ),
                sourceModule: index.isMultiple(of: 2) ? .repeatable : .astrophotography,
                projectName: "Project \(index % 50)",
                sessionName: "Session \(index)",
                sourceCreatedAt: Date(timeIntervalSince1970: TimeInterval(index)),
                duration: 5,
                pixelWidth: 1920,
                pixelHeight: 1080,
                hasAudio: false,
                fileSize: 1_000,
                isAvailable: true
            )
        }
        let snapshot = MediaLibrarySnapshot(assets: assets)
        let filter = MediaLibraryFilter(origin: .module(.repeatable), kind: .timelapse)

        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            XCTAssertEqual(snapshot.filtered(by: filter).count, 500)
        }
    }
}
