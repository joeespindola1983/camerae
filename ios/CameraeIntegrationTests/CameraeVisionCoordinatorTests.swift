import CoreVideo
import Testing
@testable import Camerae

@Suite("Camerae Vision capture coordinator")
struct CameraeVisionCoordinatorTests {
    @Test("Disabled coordinator creates no backend or worker")
    func disabledPathIsZeroWork() throws {
        let executor = ManualCameraeVisionExecutor()
        let factory = BackendFactorySpy()
        let coordinator = CameraeVisionCaptureCoordinator(
            configuration: .disabled,
            executor: executor,
            backendFactory: factory.make
        )

        coordinator.updateReference(try makePixelBuffer(seed: 1), orientation: .up)
        coordinator.submit(try makePixelBuffer(seed: 2), orientation: .up, at: 0)

        #expect(factory.creationCount == 0)
        #expect(executor.pendingCount == 0)
        #expect(coordinator.diagnostics.admitted == 0)
    }

    @Test("Slow backend evaluates the active frame and only the latest pending frame")
    func slowBackendIsLatestOnly() throws {
        let executor = ManualCameraeVisionExecutor()
        let factory = BackendFactorySpy()
        let coordinator = CameraeVisionCaptureCoordinator(
            configuration: .init(enabled: true, cadence: .responsive),
            executor: executor,
            backendFactory: factory.make
        )
        coordinator.updateReference(try makePixelBuffer(seed: 10), orientation: .up)

        coordinator.submit(try makePixelBuffer(seed: 1), orientation: .up, at: 0)
        coordinator.submit(try makePixelBuffer(seed: 2), orientation: .up, at: 0.25)
        coordinator.submit(try makePixelBuffer(seed: 3), orientation: .up, at: 0.50)

        #expect(executor.pendingCount == 1)
        executor.runNext()
        #expect(executor.pendingCount == 1)
        executor.runNext()

        #expect(factory.backend?.evaluatedMarkers == [1, 3])
        #expect(coordinator.diagnostics.replaced == 1)
        #expect(coordinator.diagnostics.maximumBacklog == 2)
    }

    @Test("Result from an old reference generation is not published")
    func oldGenerationResultIsStale() throws {
        let executor = ManualCameraeVisionExecutor()
        let factory = BackendFactorySpy()
        var published: [UInt8] = []
        let coordinator = CameraeVisionCaptureCoordinator(
            configuration: .init(enabled: true, cadence: .balanced),
            executor: executor,
            backendFactory: factory.make,
            resultHandler: { published.append($0.marker) }
        )
        coordinator.updateReference(try makePixelBuffer(seed: 10), orientation: .up)
        coordinator.submit(try makePixelBuffer(seed: 1), orientation: .up, at: 0)

        coordinator.updateReference(try makePixelBuffer(seed: 20), orientation: .up)
        executor.runNext()

        #expect(published.isEmpty)
        #expect(coordinator.diagnostics.stale == 1)
        #expect(factory.cancelCount == 1)
    }

    private func makePixelBuffer(seed: UInt8) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let attributes = [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            16,
            16,
            kCVPixelFormatType_32BGRA,
            attributes,
            &buffer
        )
        #expect(status == kCVReturnSuccess)
        let result = try #require(buffer)
        CVPixelBufferLockBaseAddress(result, [])
        CVPixelBufferGetBaseAddress(result)?.assumingMemoryBound(to: UInt8.self).pointee = seed
        CVPixelBufferUnlockBaseAddress(result, [])
        return result
    }
}

private final class ManualCameraeVisionExecutor: CameraeVisionWorkExecuting {
    private var work: [() -> Void] = []
    var pendingCount: Int { work.count }

    func execute(_ operation: @escaping () -> Void) {
        work.append(operation)
    }

    func runNext() {
        guard !work.isEmpty else { return }
        work.removeFirst()()
    }
}

private final class BackendFactorySpy {
    private(set) var creationCount = 0
    private(set) var cancelCount = 0
    private(set) var backend: BackendSpy?

    func make(reference: CVPixelBuffer, orientation: CEVImageOrientation) throws -> any CameraeVisionCaptureBackend {
        creationCount += 1
        let backend = BackendSpy(onCancel: { self.cancelCount += 1 })
        self.backend = backend
        return backend
    }
}

private final class BackendSpy: CameraeVisionCaptureBackend {
    private let onCancel: () -> Void
    private(set) var evaluatedMarkers: [UInt8] = []

    init(onCancel: @escaping () -> Void) {
        self.onCancel = onCancel
    }

    func evaluate(_ frame: CameraeVisionFrame) throws -> CameraeVisionShadowSnapshot? {
        CVPixelBufferLockBaseAddress(frame.pixelBuffer, .readOnly)
        let marker = CVPixelBufferGetBaseAddress(frame.pixelBuffer)!.assumingMemoryBound(to: UInt8.self).pointee
        CVPixelBufferUnlockBaseAddress(frame.pixelBuffer, .readOnly)
        evaluatedMarkers.append(marker)
        return CameraeVisionShadowSnapshot(marker: marker)
    }

    func cancel() { onCancel() }
    func resume() {}
}
