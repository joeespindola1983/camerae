import CoreVideo
import Testing
@testable import Camerae

@Suite("Camerae Vision OpenCV backend adapter")
struct CameraeVisionOpenCVBackendTests {
    @Test("Bridge result becomes an immutable shadow snapshot")
    func resultMapping() throws {
        let reference = try makeTexturedBuffer(seed: 41)
        let backend = try CameraeVisionOpenCVBackend(reference: reference, orientation: .up)
        let frame = CameraeVisionFrame(
            id: 1,
            generation: 7,
            pixelBuffer: reference,
            orientation: .up,
            timestamp: 12
        )

        let snapshot = try #require(try backend.evaluate(frame))

        #expect(snapshot.schemaVersion == 1)
        #expect(snapshot.transform3x3.count == 9)
        #expect(snapshot.score > 0)
        #expect(snapshot.selectedModel == "similarity")
    }

    private func makeTexturedBuffer(seed: UInt32) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let attributes = [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary
        #expect(CVPixelBufferCreate(
            kCFAllocatorDefault,
            161,
            121,
            kCVPixelFormatType_32BGRA,
            attributes,
            &buffer
        ) == kCVReturnSuccess)
        let result = try #require(buffer)
        CVPixelBufferLockBaseAddress(result, [])
        let base = CVPixelBufferGetBaseAddress(result)!.assumingMemoryBound(to: UInt8.self)
        let stride = CVPixelBufferGetBytesPerRow(result)
        var state = seed
        for row in 0..<121 {
            for column in 0..<161 {
                state = state &* 1_664_525 &+ 1_013_904_223
                let offset = row * stride + column * 4
                base[offset] = UInt8(truncatingIfNeeded: state)
                base[offset + 1] = UInt8(truncatingIfNeeded: state >> 8)
                base[offset + 2] = UInt8(truncatingIfNeeded: state >> 16)
                base[offset + 3] = 255
            }
        }
        CVPixelBufferUnlockBaseAddress(result, [])
        return result
    }
}
