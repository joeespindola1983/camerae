import CoreImage
import CoreML
import Foundation
import Vision
#if canImport(onnxruntime_objc)
import onnxruntime_objc
#endif

enum DeepSNRDenoiserError: LocalizedError {
    case modelNotFound
    case onnxRuntimeUnavailable
    case unsupportedModel
    case imageRenderingFailed
    case predictionFailed

    var errorDescription: String? {
        switch self {
        case .modelNotFound:
            return "Modelo DeepSNR nao encontrado. Adicione DeepSNR_weights_v2.onnx em ios/LocalModels/DeepSNR ou DeepSNR.mlmodel ao target Camerae."
        case .onnxRuntimeUnavailable:
            return "Modelo DeepSNR ONNX encontrado, mas o ONNX Runtime ainda nao esta linkado no app iOS."
        case .unsupportedModel:
            return "O modelo DeepSNR precisa ter uma entrada e uma saida do tipo imagem para este backend."
        case .imageRenderingFailed:
            return "Nao foi possivel preparar a imagem para o DeepSNR."
        case .predictionFailed:
            return "O DeepSNR nao retornou uma imagem valida."
        }
    }
}

final class DeepSNRDenoiser {
    static var isAvailable: Bool {
        onnxModelURL() != nil || coreMLModelURL() != nil
    }

    private enum Backend {
        case onnx(URL)
        case coreML(MLModel, inputName: String, inputConstraint: MLImageConstraint, outputName: String)
    }

    private let backend: Backend

    init() throws {
        if let onnxURL = Self.onnxModelURL() {
            backend = .onnx(onnxURL)
            return
        }

        guard let url = Self.coreMLModelURL() else {
            throw DeepSNRDenoiserError.modelNotFound
        }

        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all
        let model = try MLModel(contentsOf: url, configuration: configuration)

        guard let input = model.modelDescription.inputDescriptionsByName.first(where: { _, description in
            description.type == .image && description.imageConstraint != nil
        }), let constraint = input.value.imageConstraint else {
            throw DeepSNRDenoiserError.unsupportedModel
        }

        guard let output = model.modelDescription.outputDescriptionsByName.first(where: { _, description in
            description.type == .image
        }) else {
            throw DeepSNRDenoiserError.unsupportedModel
        }

        backend = .coreML(
            model,
            inputName: input.key,
            inputConstraint: constraint,
            outputName: output.key
        )
    }

    func denoisedImage(_ image: CIImage, context: CIContext) throws -> CIImage {
        switch backend {
        case .onnx(let url):
            return try DeepSNROnnxDenoiser(modelURL: url).denoisedImage(image, context: context)
        case .coreML(let model, let inputName, let inputConstraint, let outputName):
            return try denoisedImageWithCoreML(
                image,
                context: context,
                model: model,
                inputName: inputName,
                inputConstraint: inputConstraint,
                outputName: outputName
            )
        }
    }

    private func denoisedImageWithCoreML(
        _ image: CIImage,
        context: CIContext,
        model: MLModel,
        inputName: String,
        inputConstraint: MLImageConstraint,
        outputName: String
    ) throws -> CIImage {
        let extent = image.extent.integral
        guard let cgImage = context.createCGImage(image, from: extent) else {
            throw DeepSNRDenoiserError.imageRenderingFailed
        }

        let inputValue = try MLFeatureValue(
            cgImage: cgImage,
            constraint: inputConstraint,
            options: [.cropAndScale: VNImageCropAndScaleOption.scaleFill.rawValue]
        )
        let provider = try MLDictionaryFeatureProvider(dictionary: [inputName: inputValue])
        let output = try model.prediction(from: provider)

        guard let outputValue = output.featureValue(for: outputName),
              let outputImage = outputValue.imageBufferValue else {
            throw DeepSNRDenoiserError.predictionFailed
        }

        return CIImage(cvPixelBuffer: outputImage)
    }

    private static func onnxModelURL() -> URL? {
        if let url = Bundle.main.url(
            forResource: "DeepSNR_weights_v2",
            withExtension: "onnx",
            subdirectory: "DeepSNR"
        ) {
            return url
        }

        if let url = Bundle.main.url(forResource: "DeepSNR_weights_v2", withExtension: "onnx") {
            return url
        }

        if let urls = Bundle.main.urls(forResourcesWithExtension: "onnx", subdirectory: nil) {
            return urls.first { $0.lastPathComponent.localizedCaseInsensitiveContains("deepsnr") }
        }

        return nil
    }

    private static func coreMLModelURL() -> URL? {
        if let url = Bundle.main.url(forResource: "DeepSNR", withExtension: "mlmodelc") {
            return url
        }

        if let urls = Bundle.main.urls(forResourcesWithExtension: "mlmodelc", subdirectory: nil) {
            return urls.first { $0.deletingPathExtension().lastPathComponent.localizedCaseInsensitiveContains("deepsnr") }
        }

        return nil
    }
}

private final class DeepSNROnnxDenoiser {
    fileprivate static let tileSize = 512
    fileprivate static let stride = 480

    private let modelURL: URL

    init(modelURL: URL) {
        self.modelURL = modelURL
    }

    func denoisedImage(_ image: CIImage, context: CIContext) throws -> CIImage {
        #if canImport(onnxruntime_objc)
        let runner = try DeepSNROnnxRunner(modelURL: modelURL)
        return try runner.denoisedImage(image, context: context)
        #else
        throw DeepSNRDenoiserError.onnxRuntimeUnavailable
        #endif
    }
}

#if canImport(onnxruntime_objc)
private final class DeepSNROnnxRunner {
    private let env: ORTEnv
    private let session: ORTSession
    private let inputName: String
    private let outputName: String

    init(modelURL: URL) throws {
        env = try ORTEnv(loggingLevel: ORTLoggingLevel.warning)
        let options = try ORTSessionOptions()
        _ = try? options.setGraphOptimizationLevel(ORTGraphOptimizationLevel.all)
        _ = try? options.appendExecutionProvider("xnnpack", providerOptions: [:])
        session = try ORTSession(env: env, modelPath: modelURL.path, sessionOptions: options)

        guard let inputName = try session.inputNames().first,
              let outputName = try session.outputNames().first else {
            throw DeepSNRDenoiserError.unsupportedModel
        }

        self.inputName = inputName
        self.outputName = outputName
    }

    func denoisedImage(_ image: CIImage, context: CIContext) throws -> CIImage {
        let rgba = try renderRGBA(image, context: context)
        let width = rgba.width
        let height = rgba.height
        let pixelCount = width * height
        var accum = [Float](repeating: 0, count: pixelCount * 3)
        var weights = [Float](repeating: 0, count: pixelCount)
        let xs = tileStarts(length: width)
        let ys = tileStarts(length: height)

        for y in ys {
            for x in xs {
                let output = try runTile(rgba: rgba.bytes, width: width, height: height, originX: x, originY: y)
                blendTile(output, into: &accum, weights: &weights, width: width, height: height, originX: x, originY: y)
            }
        }

        var outputBytes = [UInt8](repeating: 255, count: pixelCount * 4)
        for index in 0..<pixelCount {
            let weight = max(weights[index], 1)
            outputBytes[index * 4] = UInt8(clamping: Int((accum[index * 3] / weight * 255).rounded()))
            outputBytes[index * 4 + 1] = UInt8(clamping: Int((accum[index * 3 + 1] / weight * 255).rounded()))
            outputBytes[index * 4 + 2] = UInt8(clamping: Int((accum[index * 3 + 2] / weight * 255).rounded()))
            outputBytes[index * 4 + 3] = 255
        }

        return try makeImage(bytes: outputBytes, width: width, height: height)
    }

    private func runTile(
        rgba: [UInt8],
        width: Int,
        height: Int,
        originX: Int,
        originY: Int
    ) throws -> [Float] {
        let tileSize = DeepSNROnnxDenoiser.tileSize
        let channelCount = 3
        let inputData = NSMutableData(length: tileSize * tileSize * channelCount * MemoryLayout<Float>.size)!
        let input = inputData.mutableBytes.assumingMemoryBound(to: Float.self)

        for tileY in 0..<tileSize {
            let sourceY = min(originY + tileY, height - 1)
            for tileX in 0..<tileSize {
                let sourceX = min(originX + tileX, width - 1)
                let sourceIndex = (sourceY * width + sourceX) * 4
                let targetIndex = (tileY * tileSize + tileX) * channelCount
                input[targetIndex] = Float(rgba[sourceIndex]) / 255
                input[targetIndex + 1] = Float(rgba[sourceIndex + 1]) / 255
                input[targetIndex + 2] = Float(rgba[sourceIndex + 2]) / 255
            }
        }

        let inputValue = try ORTValue(
            tensorData: inputData,
            elementType: ORTTensorElementDataType.float,
            shape: [1, NSNumber(value: tileSize), NSNumber(value: tileSize), NSNumber(value: channelCount)]
        )
        guard let outputs = try session.run(
            withInputs: [inputName: inputValue],
            outputNames: [outputName],
            runOptions: nil
        )[outputName] else {
            throw DeepSNRDenoiserError.predictionFailed
        }

        let outputData = try outputs.tensorData()
        let output = outputData.bytes.assumingMemoryBound(to: Float.self)
        return Array(UnsafeBufferPointer(start: output, count: tileSize * tileSize * channelCount))
    }

    private func blendTile(
        _ tile: [Float],
        into accum: inout [Float],
        weights: inout [Float],
        width: Int,
        height: Int,
        originX: Int,
        originY: Int
    ) {
        let tileSize = DeepSNROnnxDenoiser.tileSize
        for tileY in 0..<tileSize {
            let targetY = originY + tileY
            guard targetY < height else { continue }

            for tileX in 0..<tileSize {
                let targetX = originX + tileX
                guard targetX < width else { continue }

                let targetPixel = targetY * width + targetX
                let sourceIndex = (tileY * tileSize + tileX) * 3
                accum[targetPixel * 3] += min(max(tile[sourceIndex], 0), 1)
                accum[targetPixel * 3 + 1] += min(max(tile[sourceIndex + 1], 0), 1)
                accum[targetPixel * 3 + 2] += min(max(tile[sourceIndex + 2], 0), 1)
                weights[targetPixel] += 1
            }
        }
    }

    private func tileStarts(length: Int) -> [Int] {
        let tileSize = DeepSNROnnxDenoiser.tileSize
        let stride = DeepSNROnnxDenoiser.stride
        guard length > tileSize else { return [0] }

        var starts: [Int] = []
        var value = 0
        while value + tileSize < length {
            starts.append(value)
            value += stride
        }
        let last = max(length - tileSize, 0)
        if starts.last != last {
            starts.append(last)
        }
        return starts
    }

    private struct RGBAImage {
        let bytes: [UInt8]
        let width: Int
        let height: Int
    }

    private func renderRGBA(_ image: CIImage, context: CIContext) throws -> RGBAImage {
        let extent = image.extent.integral
        guard let cgImage = context.createCGImage(image, from: extent) else {
            throw DeepSNRDenoiserError.imageRenderingFailed
        }

        let width = cgImage.width
        let height = cgImage.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let bitmap = CGContext(
            data: &bytes,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ) else {
            throw DeepSNRDenoiserError.imageRenderingFailed
        }

        bitmap.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return RGBAImage(bytes: bytes, width: width, height: height)
    }

    private func makeImage(bytes: [UInt8], width: Int, height: Int) throws -> CIImage {
        var mutableBytes = bytes
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let bitmap = CGContext(
            data: &mutableBytes,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ), let image = bitmap.makeImage() else {
            throw DeepSNRDenoiserError.predictionFailed
        }

        return CIImage(cgImage: image)
    }
}
#endif
