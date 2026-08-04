import CameraeCore
import CameraeMedia
import Foundation
import Testing
import UIKit
@testable import Camerae

@Suite("App component integration", .serialized)
@MainActor
struct AppCompositionTests {
    @Test("Camera modules keep their Figma workflow themes")
    func cameraModuleThemes() {
        #expect(CameraModule.repeatable.designTheme == .repeatable)
        #expect(CameraModule.astrophotography.designTheme == .astro)
        #expect(CameraModule.edit.designTheme == .editor)
        #expect(CameraeWorkflowTheme.repeatable.assetName == "CameraeAccentRepeatable")
        #expect(CameraeWorkflowTheme.astro.assetName == "CameraeAccentAstro")
        #expect(CameraeWorkflowTheme.editor.assetName == "CameraeAccentEditor")
    }

    @Test("Repeatable video countdown remains conservative and reaches zero")
    func repeatableVideoCountdown() {
        let startedAt = Date(timeIntervalSince1970: 1_000)

        #expect(RepeatableRecordingCountdown.remainingSeconds(
            startedAt: startedAt,
            plannedDuration: 30,
            now: startedAt
        ) == 30)
        #expect(RepeatableRecordingCountdown.remainingSeconds(
            startedAt: startedAt,
            plannedDuration: 30,
            now: startedAt.addingTimeInterval(0.2)
        ) == 30)
        #expect(RepeatableRecordingCountdown.remainingSeconds(
            startedAt: startedAt,
            plannedDuration: 30,
            now: startedAt.addingTimeInterval(29.2)
        ) == 1)
        #expect(RepeatableRecordingCountdown.remainingSeconds(
            startedAt: startedAt,
            plannedDuration: 30,
            now: startedAt.addingTimeInterval(31)
        ) == 0)
        #expect(RepeatableRecordingCountdown.label(seconds: 65) == "01:05")
    }

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
        #expect(secondStore.projects.first?.summary?.sessionCount == 0)
        #expect(secondStore.projects.first?.summary?.mediaCount == 0)
        #expect((secondStore.projects.first?.summary?.totalKnownBytes ?? 0) > 0)
        #expect(secondStore.projects.first?.summary?.inventoryState == .clean)
    }

    @Test("ProjectStore publishes complete project bytes without blocking the view")
    func projectStoreStorageInventory() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CameraeProjectStorageIntegration-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ProjectStore(rootDirectory: root)
        let project = try await store.createProject(module: .repeatable, name: "Storage")
        try Data(repeating: 1, count: 7).write(
            to: project.directoryURL.appendingPathComponent("extra.dat")
        )

        await store.reloadNow()

        #expect((store.projects.first?.summary?.totalKnownBytes ?? 0) >= 7)
    }

    @Test("ProjectStore keeps an Astro capture frame as the project thumbnail")
    func astroProjectThumbnailFallback() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CameraeAstroThumbnail-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ProjectStore(rootDirectory: root)
        let project = try await store.createProject(module: .astrophotography, name: "Milky Way")
        let catalog = SessionCatalog(project: project.coreRecord)
        let session = try await catalog.createSession(captureKind: .photo)
        try await catalog.beginCapture(sessionID: session.id)
        let frameURL = try await catalog.saveFrame(Data([1, 2, 3]), sessionID: session.id, index: 1)
        try await catalog.finishCapture(sessionID: session.id)

        await store.reloadNow()

        #expect(store.projects.first?.referenceFrameURL?.standardizedFileURL == frameURL.standardizedFileURL)
    }

    @Test("ProjectStore creates and reloads an initialized Edit project")
    func editProjectComposition() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CameraeEditIntegrationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let firstStore = ProjectStore(rootDirectory: root)
        let created = try await firstStore.createProject(module: .edit, name: "Portfolio")
        let editURL = created.directoryURL.appendingPathComponent("edit.json")
        let secondStore = ProjectStore(rootDirectory: root)
        await secondStore.reloadNow()

        #expect(created.module == .edit)
        #expect(FileManager.default.fileExists(atPath: editURL.path))
        #expect(secondStore.projects.first?.module == .edit)
        #expect(secondStore.projects.first?.summary?.mediaCount == 0)
        #expect(secondStore.defaultProjectName(for: .edit, date: Date(timeIntervalSince1970: 0)).hasPrefix("Edit "))
    }

    @Test("Edit view model filters, repeats, reorders, removes, and reloads clips")
    func editViewModelTimelineWorkflow() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CameraeEditViewModelTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ProjectStore(rootDirectory: root)
        let project = try await store.createProject(module: .edit, name: "Portfolio")
        let first = Self.mediaDescriptor(index: 1, kind: .repeatableTimelapse, module: .repeatable)
        let second = Self.mediaDescriptor(index: 2, kind: .astroTimelapse, module: .astrophotography)
        let media = EditMediaLibraryStub(assets: [first, second])
        let model = EditProjectViewModel(project: project, mediaLibrary: media)

        await model.load()
        model.filter = MediaLibraryFilter(origin: .module(.repeatable), kind: .timelapse)
        #expect(model.filteredAssets.map { $0.reference.id } == [first.reference.id])
        model.toggleSelection(first.reference.id)
        await model.addSelection()
        model.toggleSelection(first.reference.id)
        await model.addSelection()
        #expect(model.document?.items.count == 2)
        let originalIDs = try #require(model.document?.items.map(\.id))
        await model.moveItem(from: 1, to: 0)
        #expect(model.document?.items.map(\.id) == [originalIDs[1], originalIDs[0]])
        await model.removeItem(at: 1)

        let reloaded = EditProjectViewModel(project: project, mediaLibrary: media)
        await reloaded.load()
        #expect(reloaded.document?.items.map(\.id) == [originalIDs[1]])
    }

    @Test("Edit playback state follows prepare, play, pause, advance, finish, and replay")
    func editPlaybackStateMachine() {
        let engine = EditPlaybackEngineStub()
        let coordinator = EditPlaybackCoordinator(engine: engine)
        let firstID = UUID(uuidString: "80000000-0000-0000-0000-000000000001")!
        let secondID = UUID(uuidString: "80000000-0000-0000-0000-000000000002")!
        let items = [
            EditPlaybackItem(id: firstID, url: URL(fileURLWithPath: "/tmp/first.mp4")),
            EditPlaybackItem(id: secondID, url: URL(fileURLWithPath: "/tmp/second.mp4"))
        ]

        coordinator.prepare(items: items)
        #expect(coordinator.state == .ready(currentItemID: firstID))
        coordinator.play()
        #expect(coordinator.state == .playing(currentItemID: firstID))
        coordinator.pause()
        #expect(coordinator.state == .paused(currentItemID: firstID))
        coordinator.play()
        engine.advance(to: secondID)
        #expect(coordinator.state == .playing(currentItemID: secondID))
        engine.finish()
        #expect(coordinator.state == .finished)
        coordinator.restart()
        #expect(coordinator.state == .playing(currentItemID: firstID))
        #expect(engine.restartCount == 1)
    }

    @Test("Edit export view model publishes progress and persists the exported path")
    func editExportWorkflow() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CameraeEditExportTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ProjectStore(rootDirectory: root)
        let project = try await store.createProject(module: .edit, name: "My Portfolio")
        let reference = Self.mediaDescriptor(index: 9, kind: .repeatableTimelapse, module: .repeatable).reference
        let document = try await EditProjectCatalog(project: project.coreRecord).append([reference])
        let descriptor = Self.mediaDescriptor(index: 9, kind: .repeatableTimelapse, module: .repeatable)
        let resolved = ResolvedMediaAsset(descriptor: descriptor, url: root.appendingPathComponent("source.mp4"))
        let composer = EditVideoComposerStub()
        let model = EditExportViewModel(project: project, composer: composer)
        let spatialAlignment = try ClipSpatialAlignmentPlanner().makePlan(
            referenceItemID: document.items[0].id,
            candidates: [.identity(itemID: document.items[0].id)]
        )

        await model.export(
            document: document,
            assets: [reference.id: resolved],
            spatialAlignment: spatialAlignment
        )

        #expect(model.progress == 1)
        #expect(model.outputURL?.lastPathComponent == "My Portfolio.mp4")
        #expect(model.errorMessage == nil)
        #expect(await composer.receivedSpatialAlignment == spatialAlignment)
        let reloaded = try await EditProjectCatalog(project: project.coreRecord).loadOrCreate()
        #expect(reloaded.lastExportRelativePath == "Exports/My Portfolio.mp4")
    }

    @Test("session cards describe image sequences and compilation state")
    func sessionCardMetadataForSequence() {
        let summary = makeSummary(kind: .timelapse, frames: 240, hasVideo: false)
        let metadata = SessionCardMetadata(summary: summary, duration: 95)

        #expect(metadata.title == "Timelapse")
        #expect(metadata.mediaDescription == "Sequência de imagens")
        #expect(metadata.frameDescription == "240 frames")
        #expect(metadata.durationDescription == "01:35")
        #expect(metadata.compilationDescription == "Aguardando compilação")
    }

    @Test("session cards distinguish ready video output")
    func sessionCardMetadataForCompiledVideo() {
        let summary = makeSummary(kind: .video, frames: 1, hasVideo: true)
        let metadata = SessionCardMetadata(summary: summary, duration: 7)

        #expect(metadata.mediaDescription == "Vídeo")
        #expect(metadata.compilationDescription == "Vídeo pronto")
    }

    @Test("timelapse store discovers and exports HEIC originals")
    func timelapseStoreSupportsHEIC() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CameraeHEICIntegrationTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let projectStore = ProjectStore(rootDirectory: root)
        let project = try await projectStore.createProject(module: .repeatable, name: "HEIC")
        let store = TimelapseSessionStore(project: project)
        let session = try store.createSession(captureKind: .timelapse)
        let plan = try CapturePlan.preset(
            .repeatableTimelapse(.fiveMinutes),
            sourceFormat: .heic,
            captureInterval: 5,
            renderFPS: 30,
            resolution: .fullHD
        )

        let frame = try store.saveFrame(Data([1, 2, 3]), in: session, index: 1, format: .heic)
        try store.saveCapturePlan(plan, in: session)

        #expect(frame.pathExtension == "heic")
        #expect(store.frameURLs(in: session) == [frame])
        let summaries = try await store.sessionSummariesFromCatalog()
        #expect(summaries.first?.frameCount == 1)
        #expect(summaries.first?.referenceFrameURL?.pathExtension == "heic")
        #expect(try store.capturePlan(in: session) == plan)
    }

    @Test("empty capture attempts are discarded without touching sessions that contain media")
    func emptyCaptureAttemptsAreDiscarded() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CameraeEmptyCaptureTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let projectStore = ProjectStore(rootDirectory: root)
        let project = try await projectStore.createProject(module: .repeatable, name: "Empty capture")
        let store = TimelapseSessionStore(project: project)
        let emptySession = try store.createSession(captureKind: .timelapse, cameraLens: .telephoto)
        let capturedSession = try store.createSession(captureKind: .timelapse, cameraLens: .wide)
        _ = try store.saveFrame(Data([1]), in: capturedSession, index: 1, format: .heic)

        #expect(try store.discardSessionIfEmpty(emptySession))
        #expect(!FileManager.default.fileExists(atPath: emptySession.directoryURL.path))
        #expect(!(try store.discardSessionIfEmpty(capturedSession)))
        #expect(FileManager.default.fileExists(atPath: capturedSession.directoryURL.path))
    }

    @Test("a new project reference replaces the previous reference on disk")
    func referenceReplacement() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CameraeReferenceReplacement-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let projectStore = ProjectStore(rootDirectory: root)
        let project = try await projectStore.createProject(module: .repeatable, name: "Reference")
        let store = TimelapseSessionStore(project: project)

        let first = try store.importReferenceImage(testImage(color: .red))
        let firstURL = try #require(store.firstFrameURL(in: first))
        let videoSession = try store.createSession(captureKind: .video)
        let staleAlignedURL = store.alignedVideoURL(for: videoSession)
        try Data([1]).write(to: staleAlignedURL)
        let second = try store.importReferenceImage(testImage(color: .blue))
        let secondURL = try #require(store.firstFrameURL(in: second))

        #expect(!FileManager.default.fileExists(atPath: firstURL.path))
        #expect(!FileManager.default.fileExists(atPath: staleAlignedURL.path))
        #expect(FileManager.default.fileExists(atPath: secondURL.path))
        #expect(store.sessionSummaries().filter { $0.captureKind == .photo }.map(\.session.id) == [second.id])
        #expect(store.firstReferenceFrameURL() == secondURL)
    }

    @Test("an EXIF-rotated camera reference is stored upright with swapped dimensions")
    func rotatedReferenceIsNormalizedBeforeStorage() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CameraeRotatedReference-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let projectStore = ProjectStore(rootDirectory: root)
        let project = try await projectStore.createProject(module: .repeatable, name: "Rotated reference")
        let store = TimelapseSessionStore(project: project)
        let rendererFormat = UIGraphicsImageRendererFormat.default()
        rendererFormat.scale = 1
        let source = UIGraphicsImageRenderer(
            size: CGSize(width: 40, height: 20),
            format: rendererFormat
        ).image { context in
            UIColor.red.setFill()
            context.cgContext.fill(CGRect(x: 0, y: 0, width: 20, height: 20))
            UIColor.blue.setFill()
            context.cgContext.fill(CGRect(x: 20, y: 0, width: 20, height: 20))
        }
        let sourceCGImage = try #require(source.cgImage)
        let rotated = UIImage(cgImage: sourceCGImage, scale: 1, orientation: .right)

        let session = try store.importReferenceImage(rotated)
        let url = try #require(store.firstFrameURL(in: session))
        let stored = try #require(UIImage(contentsOfFile: url.path))

        #expect(stored.imageOrientation == .up)
        #expect(stored.size == CGSize(width: 20, height: 40))
        #expect(session.referenceOrientation == .portrait)
    }

    @Test("edge overlay preserves the reference image orientation")
    func edgeOverlayPreservesReferenceOrientation() throws {
        let rendererFormat = UIGraphicsImageRendererFormat.default()
        rendererFormat.scale = 1
        let source = UIGraphicsImageRenderer(
            size: CGSize(width: 40, height: 20),
            format: rendererFormat
        ).image { context in
            UIColor.white.setFill()
            context.cgContext.fill(CGRect(x: 0, y: 0, width: 20, height: 20))
            UIColor.black.setFill()
            context.cgContext.fill(CGRect(x: 20, y: 0, width: 20, height: 20))
        }
        let sourceCGImage = try #require(source.cgImage)
        let rotatedReference = UIImage(
            cgImage: sourceCGImage,
            scale: 1,
            orientation: .right
        )

        let overlay = try #require(EdgeOverlayRenderer.render(
            image: rotatedReference,
            options: EdgeOverlayOptions(maxPixelDimension: 200)
        ))

        #expect(overlay.imageOrientation == rotatedReference.imageOrientation)
        #expect(overlay.size == rotatedReference.size)
    }

    @Test("EXIF and pixel-normalized references produce the same visual contour raster")
    func edgeOverlayMatchesVisualReferencePixels() throws {
        let rendererFormat = UIGraphicsImageRendererFormat.default()
        rendererFormat.scale = 1
        let source = UIGraphicsImageRenderer(
            size: CGSize(width: 64, height: 40),
            format: rendererFormat
        ).image { context in
            UIColor.black.setFill()
            context.cgContext.fill(CGRect(x: 0, y: 0, width: 64, height: 40))
            UIColor.white.setFill()
            context.cgContext.fill(CGRect(x: 5, y: 4, width: 18, height: 9))
            context.cgContext.fill(CGRect(x: 38, y: 19, width: 20, height: 15))
        }
        let sourceCGImage = try #require(source.cgImage)
        let exifReference = UIImage(
            cgImage: sourceCGImage,
            scale: 1,
            orientation: .right
        )
        let normalizedReference = visuallyNormalizedImage(exifReference)
        let options = EdgeOverlayOptions(
            tint: .green,
            stroke: EdgeOverlayStroke(detail: 0.35),
            maxPixelDimension: 200,
            backgroundOpacity: 0
        )

        let exifOverlay = try #require(EdgeOverlayRenderer.render(
            image: exifReference,
            options: options
        ))
        let normalizedOverlay = try #require(EdgeOverlayRenderer.render(
            image: normalizedReference,
            options: options
        ))
        let exifRaster = try rgbaRaster(visuallyNormalizedImage(exifOverlay))
        let normalizedRaster = try rgbaRaster(visuallyNormalizedImage(normalizedOverlay))

        #expect(exifRaster.width == normalizedRaster.width)
        #expect(exifRaster.height == normalizedRaster.height)
        let differingBytes = zip(exifRaster.bytes, normalizedRaster.bytes)
            .reduce(into: 0) { count, pair in
                if pair.0 != pair.1 {
                    count += 1
                }
            }
        #expect(exifRaster.bytes.count == normalizedRaster.bytes.count)
        #expect(differingBytes == 0)
    }

    @Test("inverting the edge overlay produces a different contrast raster")
    func edgeOverlayInversionChangesContrast() throws {
        let rendererFormat = UIGraphicsImageRendererFormat.default()
        rendererFormat.scale = 1
        let source = UIGraphicsImageRenderer(
            size: CGSize(width: 64, height: 40),
            format: rendererFormat
        ).image { context in
            UIColor.black.setFill()
            context.cgContext.fill(CGRect(x: 0, y: 0, width: 64, height: 40))
            UIColor.white.setFill()
            context.cgContext.fill(CGRect(x: 8, y: 6, width: 42, height: 23))
        }
        let normal = try #require(EdgeOverlayRenderer.render(
            image: source,
            options: EdgeOverlayOptions(inverted: false, maxPixelDimension: 200)
        ))
        let inverted = try #require(EdgeOverlayRenderer.render(
            image: source,
            options: EdgeOverlayOptions(inverted: true, maxPixelDimension: 200)
        ))
        let normalRaster = try rgbaRaster(normal)
        let invertedRaster = try rgbaRaster(inverted)
        let differingBytes = zip(normalRaster.bytes, invertedRaster.bytes)
            .reduce(into: 0) { count, pair in
                if pair.0 != pair.1 {
                    count += 1
                }
            }

        #expect(normalRaster.width == invertedRaster.width)
        #expect(normalRaster.height == invertedRaster.height)
        #expect(differingBytes > 0)
    }

    private func testImage(color: UIColor) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { context in
            color.setFill()
            context.cgContext.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
    }

    private func visuallyNormalizedImage(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }
        let sourceSize = image.cgImage.map {
            CGSize(width: CGFloat($0.width) / image.scale, height: CGFloat($0.height) / image.scale)
        } ?? image.size
        let size: CGSize
        switch image.imageOrientation {
        case .left, .leftMirrored, .right, .rightMirrored:
            size = CGSize(width: sourceSize.height, height: sourceSize.width)
        case .up, .upMirrored, .down, .downMirrored:
            size = sourceSize
        @unknown default:
            size = sourceSize
        }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = image.scale
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    private func rgbaRaster(_ image: UIImage) throws -> (width: Int, height: Int, bytes: [UInt8]) {
        let cgImage = try #require(image.cgImage)
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerRow = width * 4
        var bytes = [UInt8](repeating: 0, count: height * bytesPerRow)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try #require(CGContext(
            data: &bytes,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return (width, height, bytes)
    }

    @Test("capture planning view model publishes a blocked preflight")
    func capturePlanningViewModelBlocks() async throws {
        let now = Date(timeIntervalSince1970: 300)
        let service = CapturePreflightService(
            storageProvider: AppFixedStorageProvider(.init(
                availableForImportantUsage: 1_000,
                capturedAt: now,
                source: .testFixture
            )),
            batteryProvider: AppFixedBatteryProvider(.init(
                level: 0.8,
                state: .charging,
                isLowPowerModeEnabled: false,
                thermalState: .nominal,
                capturedAt: now
            )),
            admissionPolicy: .init(configuration: .init(
                minimumOperationalReserve: 500,
                planReserveFraction: 0,
                warningMarginFraction: 0
            ))
        )
        let model = CapturePlanningViewModel(service: service)
        let plan = try CapturePlan.preset(
            .repeatableTimelapse(.fiveMinutes),
            sourceFormat: .heic,
            captureInterval: 5,
            renderFPS: 30,
            resolution: .fullHD
        )

        await model.evaluate(
            plan: plan,
            sizeProfile: .init(bytesPerFrameUpperBound: 10),
            capabilityProfile: .init(
                supportedSourceFormats: [.heic, .jpeg],
                supportedAstroPipelines: []
            ),
            observedDrainPerHour: 0.1
        )

        #expect(model.result?.storage.decision == .blocked)
        #expect(model.result?.storage.shortfallBytes == 100)
        #expect(model.errorMessage == nil)
        #expect(!model.isLoading)
    }

    @Test("preflight presentation never enables a blocked capture")
    func blockedPreflightPresentation() {
        let storage = CaptureAdmissionResult(
            decision: .blocked,
            reason: .insufficientStorage,
            requiredBytes: 2_000,
            availableBytes: 1_000,
            shortfallBytes: 1_000
        )

        let presentation = CapturePreflightPresentation(storage: storage)

        #expect(!presentation.canStart)
        #expect(presentation.title == "Espaço insuficiente")
        #expect(presentation.detail.contains("1 KB"))
    }

    @Test("video metrics never describe encoded video as HEIC image frames")
    func videoPreflightMetrics() throws {
        let plan = try CapturePlan(
            workflow: .repeatableVideo,
            plannedDuration: 120,
            captureInterval: nil,
            sourceFormat: .heic,
            captureFPS: 30,
            renderFPS: nil,
            resolution: .ultraHD,
            astroPipeline: nil
        )
        let estimate = CaptureEstimate(
            expectedFrameCount: 3_600,
            captureBytes: 300_000_000,
            processingBytes: 0,
            publicationBytes: 30_000_000,
            renderedDuration: 120
        )

        let metrics = CapturePreflightMetricsPresentation(plan: plan, estimate: estimate)

        #expect(metrics.primary == "Vídeo 02:00")
        #expect(metrics.secondary.contains("4K"))
        #expect(metrics.secondary.contains("30 FPS"))
        #expect(!metrics.secondary.contains("HEIC"))
        #expect(!metrics.secondary.contains("frames"))
    }

    @Test("a cancelled preflight cannot publish stale mode information")
    func cancelledPreflightDoesNotPublish() async throws {
        let now = Date(timeIntervalSince1970: 400)
        let service = CapturePreflightService(
            storageProvider: DelayedStorageProvider(snapshotValue: .init(
                availableForImportantUsage: 10_000_000_000,
                capturedAt: now,
                source: .testFixture
            )),
            batteryProvider: AppFixedBatteryProvider(.unknown(at: now))
        )
        let model = CapturePlanningViewModel(service: service)
        let plan = try CapturePlan.preset(
            .repeatableTimelapse(.fiveMinutes),
            sourceFormat: .heic,
            captureInterval: 5,
            renderFPS: 30,
            resolution: .fullSensor
        )

        let task = Task {
            await model.evaluate(
                plan: plan,
                sizeProfile: .init(bytesPerFrameUpperBound: 1_000),
                capabilityProfile: .init(
                    supportedSourceFormats: [.heic, .jpeg],
                    supportedAstroPipelines: []
                ),
                observedDrainPerHour: nil
            )
        }
        try await Task.sleep(nanoseconds: 10_000_000)
        task.cancel()
        await task.value

        #expect(model.result == nil)
    }

    @Test("magnifier stays fully visible while dragging")
    func magnifierClampsToDisplayBounds() {
        let geometry = AlignmentMagnifierGeometry(
            displaySize: CGSize(width: 390, height: 844),
            lensSize: 140,
            margin: 8
        )

        #expect(geometry.clampedCenter(CGPoint(x: -40, y: 900)) == CGPoint(x: 78, y: 766))
        #expect(geometry.clampedCenter(CGPoint(x: 220, y: 300)) == CGPoint(x: 220, y: 300))
    }

    @Test("magnifier aligns the sampled point with its local center")
    func magnifierContentOffset() {
        let geometry = AlignmentMagnifierGeometry(
            displaySize: CGSize(width: 390, height: 844),
            lensSize: 140,
            margin: 8
        )

        #expect(geometry.contentOffset(samplePoint: CGPoint(x: 300, y: 200), zoom: 4) == CGSize(width: -1_130, height: -730))
    }

    @Test("magnifier zoom cycles through the supported levels")
    func magnifierZoomCycle() {
        #expect(AlignmentMagnifierZoom.two.next == .four)
        #expect(AlignmentMagnifierZoom.four.next == .six)
        #expect(AlignmentMagnifierZoom.six.next == .two)
    }

    private func makeSummary(
        kind: RepeatableCaptureKind,
        frames: Int,
        hasVideo: Bool
    ) -> TimelapseSessionSummary {
        let directory = FileManager.default.temporaryDirectory
        let session = TimelapseSession(
            id: UUID(),
            projectID: UUID(),
            module: .repeatable,
            captureKind: kind,
            referenceMotion: nil,
            referenceGeoPose: nil,
            referenceOrientation: nil,
            cameraLens: nil,
            name: "session_test",
            directoryURL: directory,
            createdAt: Date(timeIntervalSince1970: 0)
        )
        return TimelapseSessionSummary(
            session: session,
            captureKind: kind,
            frameCount: frames,
            captureDuration: 95,
            referenceFrameURL: nil,
            videoURL: kind == .timelapse && hasVideo ? directory.appendingPathComponent("timelapse.mp4") : nil,
            videoClipURL: kind == .video && hasVideo ? directory.appendingPathComponent("video.mov") : nil,
            alignedVideoURL: nil,
            isAstroProcessed: false,
            hasRenderedOutput: hasVideo
        )
    }

    private static func mediaDescriptor(
        index: Int,
        kind: MediaSourceKind,
        module: ProjectModule
    ) -> MediaAssetDescriptor {
        let projectID = UUID(uuidString: String(format: "60000000-0000-0000-0000-%012d", index))!
        let sessionID = UUID(uuidString: String(format: "70000000-0000-0000-0000-%012d", index))!
        return MediaAssetDescriptor(
            reference: MediaAssetReference(
                projectID: projectID,
                sessionID: sessionID,
                kind: kind,
                relativePath: "Sessions/session_\(index)/clip.mp4"
            ),
            sourceModule: module,
            projectName: "Project \(index)",
            sessionName: "Session \(index)",
            sourceCreatedAt: Date(timeIntervalSince1970: TimeInterval(index)),
            duration: 2,
            pixelWidth: 1920,
            pixelHeight: 1080,
            hasAudio: false,
            fileSize: 10,
            isAvailable: true
        )
    }
}

private struct AppFixedStorageProvider: StorageCapacityProviding {
    let value: StorageCapacitySnapshot
    init(_ value: StorageCapacitySnapshot) { self.value = value }
    func snapshot() async -> StorageCapacitySnapshot { value }
}

private struct AppFixedBatteryProvider: BatterySnapshotProviding {
    let value: BatterySnapshot
    init(_ value: BatterySnapshot) { self.value = value }
    func snapshot() async -> BatterySnapshot { value }
}

private struct DelayedStorageProvider: StorageCapacityProviding {
    let snapshotValue: StorageCapacitySnapshot
    func snapshot() async -> StorageCapacitySnapshot {
        try? await Task.sleep(nanoseconds: 100_000_000)
        return snapshotValue
    }
}

private actor EditVideoComposerStub: EditVideoComposing {
    private(set) var receivedSpatialAlignment: EditSpatialAlignmentPlan?

    func export(
        project: EditProjectDocument,
        assets: [MediaAssetID: ResolvedMediaAsset],
        outputURL: URL,
        progress: @escaping @Sendable (Double) async -> Void
    ) async throws -> URL {
        try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("mp4".utf8).write(to: outputURL)
        await progress(0.5)
        await progress(1)
        return outputURL
    }

    func export(
        project: EditProjectDocument,
        assets: [MediaAssetID: ResolvedMediaAsset],
        spatialAlignment: EditSpatialAlignmentPlan?,
        outputURL: URL,
        progress: @escaping @Sendable (Double) async -> Void
    ) async throws -> URL {
        receivedSpatialAlignment = spatialAlignment
        return try await export(
            project: project,
            assets: assets,
            outputURL: outputURL,
            progress: progress
        )
    }

    func cancel() async {}
}

private actor EditMediaLibraryStub: MediaLibraryProviding {
    private let snapshot: MediaLibrarySnapshot

    init(assets: [MediaAssetDescriptor]) {
        snapshot = MediaLibrarySnapshot(assets: assets)
    }

    func load() -> MediaLibrarySnapshot { snapshot }

    func resolve(_ reference: MediaAssetReference) -> ResolvedMediaAsset? { nil }

    func invalidate() {}
}

@MainActor
private final class EditPlaybackEngineStub: EditPlaybackQueueing {
    var onCurrentItemChanged: ((UUID?) -> Void)?
    private(set) var items: [EditPlaybackItem] = []
    private(set) var restartCount = 0

    func replace(with items: [EditPlaybackItem]) {
        self.items = items
    }

    func play() {}
    func pause() {}
    func removeAll() { items = [] }

    func restart() {
        restartCount += 1
        onCurrentItemChanged?(items.first?.id)
    }

    func advance(to id: UUID) {
        onCurrentItemChanged?(id)
    }

    func finish() {
        onCurrentItemChanged?(nil)
    }
}
