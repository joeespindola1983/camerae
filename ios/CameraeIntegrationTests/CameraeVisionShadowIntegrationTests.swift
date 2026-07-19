import CoreGraphics
import CoreVideo
import Testing
@testable import Camerae

@Suite("Camerae Vision shadow integration")
struct CameraeVisionShadowIntegrationTests {
    @Test("Release default is disabled")
    func defaultOff() {
        #expect(CameraeVisionFeatureConfiguration.releaseDefault == .disabled)
    }

    @Test("Reference conversion produces in-memory BGRA without encoding")
    func cgImageToPixelBuffer() throws {
        let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(
            data: nil,
            width: 13,
            height: 9,
            bitsPerComponent: 8,
            bytesPerRow: 13 * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 13, height: 9))
        let image = try #require(context.makeImage())

        let buffer = try CameraeVisionPixelBufferFactory.makeBGRA(from: image)

        #expect(CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_32BGRA)
        #expect(CVPixelBufferGetWidth(buffer) == 13)
        #expect(CVPixelBufferGetHeight(buffer) == 9)
        #expect(CVPixelBufferGetBytesPerRow(buffer) >= 13 * 4)
    }
}
