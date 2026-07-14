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
}
