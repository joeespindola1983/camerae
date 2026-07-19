import CameraeCore
import CameraeMedia
import Foundation

@MainActor
final class EditExportViewModel: ObservableObject {
    @Published private(set) var progress: Double = 0
    @Published private(set) var isExporting = false
    @Published private(set) var outputURL: URL?
    @Published var errorMessage: String?

    private let project: CameraProject
    private let composer: any EditVideoComposing
    private let catalog: EditProjectCatalog

    init(project: CameraProject, composer: any EditVideoComposing = EditVideoComposer()) {
        self.project = project
        self.composer = composer
        catalog = EditProjectCatalog(project: project.coreRecord)
    }

    func export(
        document: EditProjectDocument,
        assets: [MediaAssetID: ResolvedMediaAsset],
        spatialAlignment: EditSpatialAlignmentPlan? = nil
    ) async {
        guard !isExporting else { return }
        isExporting = true
        progress = 0
        outputURL = nil
        errorMessage = nil
        defer { isExporting = false }

        let filename = "\(safeFilename(project.name)).mp4"
        let relativePath = "Exports/\(filename)"
        let destination = project.directoryURL.appendingPathComponent(relativePath)
        do {
            let result = try await composer.export(
                project: document,
                assets: assets,
                spatialAlignment: spatialAlignment,
                outputURL: destination
            ) { value in
                await self.updateProgress(value)
            }
            _ = try await catalog.setLastExport(relativePath: relativePath)
            outputURL = result
            progress = 1
        } catch EditVideoComposerError.cancelled {
            errorMessage = nil
        } catch is CancellationError {
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func cancel() {
        Task { await composer.cancel() }
    }

    private func updateProgress(_ value: Double) {
        progress = min(max(value, 0), 1)
    }

    private func safeFilename(_ value: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let cleaned = value.components(separatedBy: forbidden).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Camerae Edit" : cleaned
    }
}
