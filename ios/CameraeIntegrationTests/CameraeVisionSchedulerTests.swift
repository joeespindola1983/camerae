import CoreVideo
import Testing
@testable import Camerae

@Suite("Camerae Vision scheduler")
struct CameraeVisionSchedulerTests {
    @Test("Disabled policy admits no work")
    func disabledAdmitsNothing() {
        var policy = CameraeVisionSchedulingPolicy(configuration: .disabled)

        #expect(policy.submit(frameID: 1, at: 0) == .discarded(.disabled))
        #expect(policy.diagnostics.admitted == 0)
    }

    @Test("Cadence profiles admit at 1, 2, and 4 Hz without sleeping", arguments: [
        (CameraeVisionCadence.conservative, 1.0),
        (.balanced, 0.5),
        (.responsive, 0.25)
    ])
    func deterministicCadence(profile: CameraeVisionCadence, interval: TimeInterval) {
        var policy = CameraeVisionSchedulingPolicy(configuration: .init(enabled: true, cadence: profile))

        #expect(policy.submit(frameID: 1, at: 10) == .start(frameID: 1, generation: 0))
        _ = policy.complete(frameID: 1, generation: 0, at: 10)
        #expect(policy.submit(frameID: 2, at: 10 + interval - 0.001) == .discarded(.cadence))
        #expect(policy.submit(frameID: 3, at: 10 + interval) == .start(frameID: 3, generation: 0))
    }

    @Test("Slow backend keeps one active frame and only the latest pending frame")
    func latestOnlyBackpressure() {
        var policy = CameraeVisionSchedulingPolicy(configuration: .init(enabled: true, cadence: .responsive))

        #expect(policy.submit(frameID: 1, at: 0) == .start(frameID: 1, generation: 0))
        #expect(policy.submit(frameID: 2, at: 0.25) == .pending(frameID: 2, replacedFrameID: nil))
        #expect(policy.submit(frameID: 3, at: 0.50) == .pending(frameID: 3, replacedFrameID: 2))
        #expect(policy.complete(frameID: 1, generation: 0, at: 0.75) == .start(frameID: 3, generation: 0))
        #expect(policy.diagnostics.maximumBacklog == 2)
        #expect(policy.diagnostics.replaced == 1)
    }

    @Test("Reference generation invalidates active and pending results")
    func staleGenerationIsIgnored() {
        var policy = CameraeVisionSchedulingPolicy(configuration: .init(enabled: true, cadence: .balanced))
        #expect(policy.submit(frameID: 1, at: 0) == .start(frameID: 1, generation: 0))
        #expect(policy.submit(frameID: 2, at: 0.5) == .pending(frameID: 2, replacedFrameID: nil))

        policy.advanceGeneration()

        #expect(policy.complete(frameID: 1, generation: 0, at: 1) == .none)
        #expect(policy.diagnostics.stale == 1)
        #expect(policy.pendingFrameID == nil)
    }

    @Test("Pause reasons compose and resume independently")
    func composablePauseReasons() {
        var policy = CameraeVisionSchedulingPolicy(configuration: .init(enabled: true, cadence: .balanced))

        policy.pause(.photoCapture)
        policy.pause(.thermal)
        policy.resume(.photoCapture)
        #expect(policy.submit(frameID: 1, at: 0) == .discarded(.paused))

        policy.resume(.thermal)
        #expect(policy.submit(frameID: 2, at: 0) == .start(frameID: 2, generation: 0))
    }

    @Test("Repeated failures enter a deterministic cooldown")
    func consecutiveFailureCooldown() {
        var policy = CameraeVisionSchedulingPolicy(configuration: .init(
            enabled: true,
            cadence: .responsive,
            consecutiveFailureLimit: 3,
            cooldownDuration: 5
        ))

        for id in 1...3 {
            #expect(policy.submit(frameID: UInt64(id), at: Double(id)) == .start(frameID: UInt64(id), generation: 0))
            _ = policy.fail(frameID: UInt64(id), generation: 0, at: Double(id))
        }
        #expect(policy.submit(frameID: 4, at: 7.99) == .discarded(.cooldown))
        #expect(policy.submit(frameID: 5, at: 8) == .start(frameID: 5, generation: 0))
    }
}
