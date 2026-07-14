import Foundation
import Testing
@testable import CameraeCore

@Suite("Capture planning domain")
struct CapturePlanningTests {
    @Test("presets resolve to durable values instead of preset identifiers")
    func presetsResolveToPlans() throws {
        let plan = try CapturePlan.preset(
            .astro(.oneHour),
            sourceFormat: .heic,
            captureInterval: 5,
            renderFPS: 30,
            resolution: .fullSensor,
            astroPipeline: .full
        )

        #expect(plan.workflow == .astro)
        #expect(plan.plannedDuration == 3_600)
        #expect(plan.captureInterval == 5)
        #expect(plan.sourceFormat == .heic)
        #expect(plan.renderFPS == 30)
    }

    @Test("timelapse estimate rounds frames and bytes conservatively")
    func timelapseEstimate() throws {
        let plan = try CapturePlan(
            workflow: .repeatableTimelapse,
            plannedDuration: 301,
            captureInterval: 5,
            sourceFormat: .heic,
            captureFPS: nil,
            renderFPS: 30,
            resolution: .fullHD,
            astroPipeline: nil
        )

        let estimate = try CapturePlanEstimator().estimate(
            plan: plan,
            sizeProfile: .init(bytesPerFrameUpperBound: 2_000_000)
        )

        #expect(estimate.expectedFrameCount == 61)
        #expect(estimate.captureBytes == 122_000_000)
        #expect(estimate.renderedDuration == 61.0 / 30.0)
    }

    @Test("video estimates from a conservative bitrate")
    func videoEstimate() throws {
        let plan = try CapturePlan.preset(
            .repeatableVideo(.thirtySeconds),
            sourceFormat: .heic,
            captureFPS: 30,
            resolution: .fullHD
        )
        let estimate = try CapturePlanEstimator().estimate(
            plan: plan,
            sizeProfile: .init(videoBitsPerSecondUpperBound: 12_000_000)
        )

        #expect(estimate.expectedFrameCount == 900)
        #expect(estimate.captureBytes == 45_000_000)
        #expect(estimate.renderedDuration == 30)
    }

    @Test("invalid workflow combinations are rejected before capture")
    func invalidPlans() {
        #expect(throws: CapturePlanError.self) {
            try CapturePlan(
                workflow: .astro,
                plannedDuration: 3_600,
                captureInterval: nil,
                sourceFormat: .heic,
                captureFPS: nil,
                renderFPS: 30,
                resolution: .fullSensor,
                astroPipeline: .full
            )
        }
        #expect(throws: CapturePlanError.self) {
            try CapturePlan(
                workflow: .repeatableVideo,
                plannedDuration: 30,
                captureInterval: 1,
                sourceFormat: .heic,
                captureFPS: 30,
                renderFPS: nil,
                resolution: .fullHD,
                astroPipeline: nil
            )
        }
    }

    @Test("admission reserves finalization space and blocks exact shortfall")
    func admissionPolicy() throws {
        let estimate = CaptureEstimate(
            expectedFrameCount: 100,
            captureBytes: 1_000,
            processingBytes: 200,
            publicationBytes: 300,
            renderedDuration: 4
        )
        let policy = CaptureAdmissionPolicy(
            configuration: .init(
                minimumOperationalReserve: 500,
                planReserveFraction: 0.1,
                warningMarginFraction: 0
            )
        )

        #expect(policy.evaluate(estimate: estimate, availableBytes: 2_000).decision == .allowed)
        let blocked = policy.evaluate(estimate: estimate, availableBytes: 1_999)
        #expect(blocked.decision == .blocked)
        #expect(blocked.reason == .insufficientStorage)
        #expect(blocked.shortfallBytes == 1)
    }

    @Test("unknown storage never becomes an implicit approval")
    func unknownCapacity() {
        let estimate = CaptureEstimate(
            expectedFrameCount: 1,
            captureBytes: 1,
            processingBytes: 0,
            publicationBytes: 0,
            renderedDuration: nil
        )
        let result = CaptureAdmissionPolicy().evaluate(estimate: estimate, availableBytes: nil)

        #expect(result.decision == .unknown)
        #expect(result.reason == .capacityUnavailable)
    }

    @Test("extreme plans fail explicitly instead of wrapping or trapping")
    func arithmeticOverflow() throws {
        let plan = try CapturePlan(
            workflow: .repeatableVideo,
            plannedDuration: .greatestFiniteMagnitude,
            captureInterval: nil,
            sourceFormat: .heic,
            captureFPS: 60,
            renderFPS: nil,
            resolution: .ultraHD,
            astroPipeline: nil
        )

        #expect(throws: CapturePlanError.arithmeticOverflow) {
            try CapturePlanEstimator().estimate(
                plan: plan,
                sizeProfile: .init(videoBitsPerSecondUpperBound: .max)
            )
        }
    }

    @Test("capture run budget stops at the exact planned deadline")
    func captureRunBudgetDeadline() {
        let start = Date(timeIntervalSince1970: 1_000)
        let budget = CaptureRunBudget(startedAt: start, plannedDuration: 300)

        #expect(!budget.hasReachedLimit(at: start.addingTimeInterval(299.999)))
        #expect(budget.hasReachedLimit(at: start.addingTimeInterval(300)))
        #expect(budget.remainingDuration(at: start.addingTimeInterval(120)) == 180)
        #expect(budget.remainingDuration(at: start.addingTimeInterval(400)) == 0)
    }

    @Test("runtime storage guard warns early and stops before consuming finalization reserve")
    func runtimeStorageGuard() {
        let guardPolicy = CaptureStorageGuard(
            completionReserveBytes: 500,
            bytesPerFrameUpperBound: 100,
            warningFrameCount: 2
        )

        #expect(guardPolicy.evaluate(availableBytes: 801).decision == .healthy)
        #expect(guardPolicy.evaluate(availableBytes: 800).decision == .warning)
        #expect(guardPolicy.evaluate(availableBytes: 599).decision == .stop)
        #expect(guardPolicy.evaluate(availableBytes: nil).reason == .capacityUnavailable)
    }
}

@Suite("Capture capability and energy planning")
struct CaptureCapabilityPlanningTests {
    @Test("HEIC remains selected when the complete pipeline supports it")
    func keepsHEIC() throws {
        let profile = DeviceCapabilityProfile(
            supportedSourceFormats: [.heic, .jpeg],
            supportedAstroPipelines: [.starsTimelapse]
        )

        let result = try CaptureFormatResolver().resolve(preferred: .heic, profile: profile)

        #expect(result.selectedFormat == .heic)
        #expect(result.fallbackReason == nil)
    }

    @Test("unsupported HEIC falls back to JPEG explicitly before capture")
    func fallsBackToJPEG() throws {
        let profile = DeviceCapabilityProfile(
            supportedSourceFormats: [.jpeg],
            supportedAstroPipelines: [.starsTimelapse]
        )

        let result = try CaptureFormatResolver().resolve(preferred: .heic, profile: profile)

        #expect(result.selectedFormat == .jpeg)
        #expect(result.fallbackReason == .preferredFormatUnavailable)
    }

    @Test("a device without a processed format cannot start silently")
    func rejectsMissingFormats() {
        let profile = DeviceCapabilityProfile(
            supportedSourceFormats: [],
            supportedAstroPipelines: []
        )

        #expect(throws: CaptureFormatResolutionError.noSupportedProcessedFormat) {
            try CaptureFormatResolver().resolve(preferred: .heic, profile: profile)
        }
    }

    @Test("energy estimates expose a range and recommend power for long Astro")
    func estimatesEnergyRange() throws {
        let plan = try CapturePlan.preset(
            .astro(.threeHours),
            sourceFormat: .heic,
            captureInterval: 5,
            renderFPS: 30,
            resolution: .fullSensor,
            astroPipeline: .full
        )
        let snapshot = BatterySnapshot(
            level: 0.80,
            state: .unplugged,
            isLowPowerModeEnabled: false,
            thermalState: .nominal,
            capturedAt: Date(timeIntervalSince1970: 1)
        )

        let result = CaptureEnergyEstimator().estimate(
            plan: plan,
            snapshot: snapshot,
            observedDrainPerHour: 0.15,
            uncertaintyFraction: 0.20
        )

        #expect(result.decision == .warning)
        #expect(abs(result.estimatedEndLevel.lowerBound - 0.26) < 0.000_001)
        #expect(abs(result.estimatedEndLevel.upperBound - 0.44) < 0.000_001)
        #expect(result.externalPowerRecommended)
    }

    @Test("unknown battery data remains unknown")
    func unknownEnergy() throws {
        let plan = try CapturePlan.preset(
            .repeatableTimelapse(.fiveMinutes),
            sourceFormat: .jpeg,
            captureInterval: 5,
            renderFPS: 30,
            resolution: .fullHD
        )
        let result = CaptureEnergyEstimator().estimate(
            plan: plan,
            snapshot: .unknown(at: Date(timeIntervalSince1970: 1)),
            observedDrainPerHour: nil
        )

        #expect(result.decision == .unknown)
        #expect(result.confidence == .low)
    }

    @Test("Astro pipeline degrades deterministically with device pressure")
    func resolvesAstroPipelineBudget() {
        let resolver = AstroPipelineResolver()

        #expect(resolver.resolve(.init(
            physicalMemoryBytes: 6 * 1_024 * 1_024 * 1_024,
            thermalState: .nominal,
            isLowPowerModeEnabled: false
        )) == .full)
        #expect(resolver.resolve(.init(
            physicalMemoryBytes: 3 * 1_024 * 1_024 * 1_024,
            thermalState: .fair,
            isLowPowerModeEnabled: true
        )) == .reduced)
        #expect(resolver.resolve(.init(
            physicalMemoryBytes: 2 * 1_024 * 1_024 * 1_024,
            thermalState: .critical,
            isLowPowerModeEnabled: false
        )) == .starsTimelapse)
    }
}

@Suite("Capture plan persistence")
struct CapturePlanPersistenceTests {
    @Test("a resolved plan round-trips through its versioned document")
    func roundTrip() throws {
        let plan = try CapturePlan.preset(
            .astro(.oneHour),
            sourceFormat: .heic,
            captureInterval: 5,
            renderFPS: 24,
            resolution: .fullSensor,
            astroPipeline: .reduced
        )
        let codec = CapturePlanCodec()

        let decoded = try codec.decode(codec.encode(plan))

        #expect(decoded.schemaVersion == 1)
        #expect(decoded.plan == plan)
    }

    @Test("future schemas are rejected explicitly")
    func rejectsFutureSchema() {
        let json = #"""
        {
          "schemaVersion": 99,
          "plan": {
            "workflow": "repeatableTimelapse",
            "plannedDuration": 300,
            "captureInterval": 5,
            "sourceFormat": "jpeg",
            "renderFPS": 30,
            "resolution": "fullHD"
          }
        }
        """#

        #expect(throws: CapturePlanCodecError.unsupportedSchema(99)) {
            try CapturePlanCodec().decode(Data(json.utf8))
        }
    }

    @Test("decoded plans are validated instead of trusting JSON")
    func rejectsInvalidValues() {
        let json = #"""
        {
          "schemaVersion": 1,
          "plan": {
            "workflow": "repeatableTimelapse",
            "plannedDuration": -1,
            "captureInterval": 5,
            "sourceFormat": "jpeg",
            "renderFPS": 30,
            "resolution": "fullHD"
          }
        }
        """#

        #expect(throws: CapturePlanError.invalidDuration) {
            try CapturePlanCodec().decode(Data(json.utf8))
        }
    }
}

@Suite("Capture preflight service")
struct CapturePreflightServiceTests {
    @Test("preflight resolves format and blocks a plan that cannot finish")
    func blocksInsufficientStorage() async throws {
        let now = Date(timeIntervalSince1970: 100)
        let storage = FixedStorageCapacityProvider(
            StorageCapacitySnapshot(
                availableForImportantUsage: 1_000,
                capturedAt: now,
                source: .testFixture
            )
        )
        let battery = FixedBatterySnapshotProvider(
            BatterySnapshot(
                level: 0.9,
                state: .charging,
                isLowPowerModeEnabled: false,
                thermalState: .nominal,
                capturedAt: now
            )
        )
        let service = CapturePreflightService(
            storageProvider: storage,
            batteryProvider: battery,
            admissionPolicy: CaptureAdmissionPolicy(
                configuration: .init(
                    minimumOperationalReserve: 500,
                    planReserveFraction: 0,
                    warningMarginFraction: 0
                )
            )
        )
        let plan = try CapturePlan.preset(
            .repeatableTimelapse(.fiveMinutes),
            sourceFormat: .heic,
            captureInterval: 5,
            renderFPS: 30,
            resolution: .fullHD
        )

        let result = try await service.evaluate(
            plan: plan,
            sizeProfile: .init(bytesPerFrameUpperBound: 10),
            capabilityProfile: .init(
                supportedSourceFormats: [.jpeg],
                supportedAstroPipelines: []
            ),
            observedDrainPerHour: 0.1
        )

        #expect(result.resolvedPlan.sourceFormat == .jpeg)
        #expect(result.formatFallbackReason == .preferredFormatUnavailable)
        #expect(result.estimate.expectedFrameCount == 60)
        #expect(result.storage.decision == .blocked)
        #expect(result.storage.shortfallBytes == 100)
        #expect(result.energy.decision == .sufficient)
    }

    @Test("volume provider reads important-usage capacity from the project volume")
    func readsVolumeCapacity() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CameraeCapacityTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let date = Date(timeIntervalSince1970: 200)

        let snapshot = await VolumeStorageCapacityProvider(
            rootURL: root,
            dateProvider: FixedDateProvider(date)
        ).snapshot()

        #expect(snapshot.availableForImportantUsage != nil)
        #expect((snapshot.availableForImportantUsage ?? 0) > 0)
        #expect(snapshot.capturedAt == date)
        #expect(snapshot.source == .importantUsage)
    }
}

private struct FixedStorageCapacityProvider: StorageCapacityProviding {
    let value: StorageCapacitySnapshot
    init(_ value: StorageCapacitySnapshot) { self.value = value }
    func snapshot() async -> StorageCapacitySnapshot { value }
}

private struct FixedBatterySnapshotProvider: BatterySnapshotProviding {
    let value: BatterySnapshot
    init(_ value: BatterySnapshot) { self.value = value }
    func snapshot() async -> BatterySnapshot { value }
}
