import CoreVideo
import Foundation

final class CameraeVisionOpenCVBackend: CameraeVisionCaptureBackend {
    private let session: CameraeVisionCaptureSession

    init(reference: CVPixelBuffer, orientation: CEVImageOrientation) throws {
        self.session = try CameraeVisionCaptureSession(
            referencePixelBuffer: reference,
            orientation: orientation
        )
    }

    func evaluate(_ frame: CameraeVisionFrame) throws -> CameraeVisionShadowSnapshot? {
        let result = try session.evaluatePixelBuffer(
            frame.pixelBuffer,
            orientation: frame.orientation
        )

        return CameraeVisionShadowSnapshot(
            schemaVersion: result.schemaVersion,
            decision: result.decision.rawValue,
            score: result.score,
            overlapRatio: result.overlapRatio,
            reprojectionRMSE: result.reprojectionRMSE,
            edgeAlignmentError: result.edgeAlignmentError,
            latencyMilliseconds: result.latencyMilliseconds,
            selectedModel: result.selectedModel,
            reasonCodes: result.reasonCodes,
            transform3x3: result.transform3x3.map { $0.doubleValue }
        )
    }

    func cancel() {
        session.cancel()
    }

    func resume() {
        session.resume()
    }
}
