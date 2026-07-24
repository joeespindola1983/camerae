import AVFoundation
import CameraeMedia
import CoreVideo
import Foundation

struct VideoClipAlignmentSource: Hashable, Sendable {
    let itemID: UUID
    let url: URL
    let duration: TimeInterval
    let fingerprint: String

    init(itemID: UUID, url: URL, duration: TimeInterval, fingerprint: String = "") {
        self.itemID = itemID
        self.url = url
        self.duration = duration
        self.fingerprint = fingerprint
    }
}

final class VideoClipAlignmentFrame: @unchecked Sendable {
    let pixelBuffer: CVPixelBuffer

    init(pixelBuffer: CVPixelBuffer) {
        self.pixelBuffer = pixelBuffer
    }
}

struct VideoClipAlignmentMeasurement: Equatable, Sendable {
    let model: ClipAlignmentMotionModel
    let transform: ClipAlignmentTransform
    let validRegion: ClipAlignmentNormalizedRect
    let quality: ClipAlignmentQuality

    static func rejected(reason: String) -> Self {
        Self(
            model: .translation,
            transform: .identity,
            validRegion: .full,
            quality: .init(decision: .reject, score: 0, reasonCodes: [reason])
        )
    }
}

protocol VideoClipAlignmentFrameExtracting: Sendable {
    func frames(
        for source: VideoClipAlignmentSource,
        fractions: [Double]
    ) async throws -> [VideoClipAlignmentFrame]
}

protocol VideoClipAlignmentPairEvaluating: Sendable {
    func evaluate(
        reference: VideoClipAlignmentFrame,
        moving: VideoClipAlignmentFrame
    ) async throws -> VideoClipAlignmentMeasurement
}

struct VideoClipAlignmentDiagnostics: Equatable, Sendable {
    let cacheHit: Bool
    let sampledFrameCount: Int
    let evaluatedPairCount: Int

    static let empty = Self(cacheHit: false, sampledFrameCount: 0, evaluatedPairCount: 0)
}

actor VideoClipAlignmentAnalyzer {
    private struct ReferenceCacheKey: Hashable {
        let referenceFingerprint: String
        let source: VideoClipAlignmentSource
    }

    static let sampleFractions = [0.1, 0.3, 0.5, 0.7, 0.9]
    private static let cacheCapacity = 8

    private let extractor: any VideoClipAlignmentFrameExtracting
    private let evaluator: any VideoClipAlignmentPairEvaluating
    private let planner: ClipSpatialAlignmentPlanner
    private var cachedPlans: [[VideoClipAlignmentSource]: EditSpatialAlignmentPlan] = [:]
    private var cacheOrder: [[VideoClipAlignmentSource]] = []
    private var cachedReferencePlans: [ReferenceCacheKey: EditSpatialAlignmentPlan] = [:]
    private var referenceCacheOrder: [ReferenceCacheKey] = []
    private(set) var lastDiagnostics = VideoClipAlignmentDiagnostics.empty

    init(
        extractor: any VideoClipAlignmentFrameExtracting,
        evaluator: any VideoClipAlignmentPairEvaluating,
        planner: ClipSpatialAlignmentPlanner = ClipSpatialAlignmentPlanner()
    ) {
        self.extractor = extractor
        self.evaluator = evaluator
        self.planner = planner
    }

    func analyze(sources: [VideoClipAlignmentSource]) async throws -> EditSpatialAlignmentPlan {
        try Task.checkCancellation()
        if let cached = cachedPlans[sources] {
            lastDiagnostics = .init(cacheHit: true, sampledFrameCount: 0, evaluatedPairCount: 0)
            return cached
        }
        lastDiagnostics = .empty
        guard let referenceSource = sources.first else {
            throw VideoClipAlignmentAnalysisError.emptyTimeline
        }
        guard Set(sources.map(\.itemID)).count == sources.count else {
            throw VideoClipAlignmentAnalysisError.duplicateItem
        }
        guard sources.allSatisfy({ $0.duration.isFinite && $0.duration > 0 }) else {
            throw VideoClipAlignmentAnalysisError.invalidDuration
        }

        let referenceFrames = try await extractor.frames(
            for: referenceSource,
            fractions: Self.sampleFractions
        )
        var sampledFrameCount = referenceFrames.count
        var evaluatedPairCount = 0
        guard referenceFrames.count == Self.sampleFractions.count else {
            throw VideoClipAlignmentAnalysisError.insufficientReferenceSamples
        }

        var candidates: [ClipAlignmentCandidate] = [.identity(itemID: referenceSource.itemID)]
        for source in sources.dropFirst() {
            try Task.checkCancellation()
            let movingFrames = try await extractor.frames(for: source, fractions: Self.sampleFractions)
            sampledFrameCount += movingFrames.count
            guard movingFrames.count == referenceFrames.count else {
                candidates.append(rejectedCandidate(itemID: source.itemID, reason: "insufficientSamples"))
                continue
            }

            var measurements: [VideoClipAlignmentMeasurement] = []
            for (index, pair) in zip(referenceFrames, movingFrames).enumerated() {
                try Task.checkCancellation()
                let measurement = try await evaluator.evaluate(
                    reference: pair.0,
                    moving: pair.1
                )
                measurements.append(measurement)
                logSample(measurement, fraction: Self.sampleFractions[index], sourceIndex: candidates.count)
                evaluatedPairCount += 1
            }
            candidates.append(consensus(itemID: source.itemID, measurements: measurements))
        }

        try Task.checkCancellation()
        let plan = try planner.makePlan(
            referenceItemID: referenceSource.itemID,
            candidates: candidates
        )
        lastDiagnostics = .init(
            cacheHit: false,
            sampledFrameCount: sampledFrameCount,
            evaluatedPairCount: evaluatedPairCount
        )
        cache(plan, for: sources)
        return plan
    }

    func analyze(
        referenceFrame: VideoClipAlignmentFrame,
        referenceFingerprint: String,
        source: VideoClipAlignmentSource
    ) async throws -> EditSpatialAlignmentPlan {
        try Task.checkCancellation()
        guard source.duration.isFinite, source.duration > 0 else {
            throw VideoClipAlignmentAnalysisError.invalidDuration
        }
        let cacheKey = ReferenceCacheKey(
            referenceFingerprint: referenceFingerprint,
            source: source
        )
        if let cached = cachedReferencePlans[cacheKey] {
            lastDiagnostics = .init(cacheHit: true, sampledFrameCount: 0, evaluatedPairCount: 0)
            return cached
        }

        let movingFrames = try await extractor.frames(
            for: source,
            fractions: Self.sampleFractions
        )
        guard movingFrames.count == Self.sampleFractions.count else {
            throw VideoClipAlignmentAnalysisError.insufficientReferenceSamples
        }
        var measurements: [VideoClipAlignmentMeasurement] = []
        measurements.reserveCapacity(movingFrames.count)
        for (index, movingFrame) in movingFrames.enumerated() {
            try Task.checkCancellation()
            let measurement = try await evaluator.evaluate(
                reference: referenceFrame,
                moving: movingFrame
            )
            measurements.append(measurement)
            logSample(measurement, fraction: Self.sampleFractions[index], sourceIndex: 0)
        }

        let candidate = consensus(itemID: source.itemID, measurements: measurements)
        let plan = try planner.makePlan(
            referenceItemID: source.itemID,
            candidates: [candidate]
        )
        lastDiagnostics = .init(
            cacheHit: false,
            sampledFrameCount: movingFrames.count + 1,
            evaluatedPairCount: measurements.count
        )
        cache(plan, for: cacheKey)
        return plan
    }

    private func cache(_ plan: EditSpatialAlignmentPlan, for sources: [VideoClipAlignmentSource]) {
        if cachedPlans[sources] == nil {
            cacheOrder.append(sources)
        }
        cachedPlans[sources] = plan
        while cacheOrder.count > Self.cacheCapacity {
            cachedPlans.removeValue(forKey: cacheOrder.removeFirst())
        }
    }

    private func cache(_ plan: EditSpatialAlignmentPlan, for key: ReferenceCacheKey) {
        if cachedReferencePlans[key] == nil {
            referenceCacheOrder.append(key)
        }
        cachedReferencePlans[key] = plan
        while referenceCacheOrder.count > Self.cacheCapacity {
            cachedReferencePlans.removeValue(forKey: referenceCacheOrder.removeFirst())
        }
    }

    private func consensus(
        itemID: UUID,
        measurements: [VideoClipAlignmentMeasurement]
    ) -> ClipAlignmentCandidate {
        let recoverableLocalResiduals = measurements.filter(isRecoverableLocalResidual)
        let recovered = recoverableLocalResiduals.count >= 3
            ? recoverableLocalResiduals.map(recoveredLocalResidual)
            : []
        let usable = measurements.filter { $0.quality.decision != .reject } + recovered
        guard usable.count >= 2 else {
            let reasons = measurements.flatMap(\.quality.reasonCodes)
            return rejectedCandidate(
                itemID: itemID,
                reason: reasons.first ?? "insufficientConsensus"
            )
        }

        guard let selected = bestConsistentMeasurements(from: usable),
              let selectedModel = selected.first?.model else {
            return rejectedCandidate(itemID: itemID, reason: "inconsistentMotionModel")
        }

        let transform = ClipAlignmentTransform(
            a: median(selected.map(\.transform.a)),
            b: median(selected.map(\.transform.b)),
            c: median(selected.map(\.transform.c)),
            d: median(selected.map(\.transform.d)),
            tx: median(selected.map(\.transform.tx)),
            ty: median(selected.map(\.transform.ty))
        )
        guard transformSpread(selected, around: transform) <= 0.025,
              let validRegion = intersect(selected.map(\.validRegion)) else {
            return rejectedCandidate(itemID: itemID, reason: "unstableTransform")
        }

        let decision: ClipAlignmentDecision = selected.contains(where: {
            $0.quality.decision == .review
        }) ? .review : .apply
        return ClipAlignmentCandidate(
            itemID: itemID,
            model: selectedModel,
            transform: transform,
            validRegion: validRegion,
            quality: .init(
                decision: decision,
                score: selected.map(\.quality.score).min() ?? 0,
                reasonCodes: Array(Set(selected.flatMap(\.quality.reasonCodes))).sorted()
            )
        )
    }

    private func isRecoverableLocalResidual(
        _ measurement: VideoClipAlignmentMeasurement
    ) -> Bool {
        measurement.quality.decision == .reject &&
            measurement.quality.score >= 0.55 &&
            measurement.transform.isFinite &&
            Set(measurement.quality.reasonCodes) == ["highLocalResidual"]
    }

    private func recoveredLocalResidual(
        _ measurement: VideoClipAlignmentMeasurement
    ) -> VideoClipAlignmentMeasurement {
        VideoClipAlignmentMeasurement(
            model: measurement.model,
            transform: measurement.transform,
            validRegion: measurement.validRegion,
            quality: .init(
                decision: .review,
                score: measurement.quality.score,
                reasonCodes: measurement.quality.reasonCodes +
                    ["temporallyConsistentLocalResidual"]
            )
        )
    }

    private func bestConsistentMeasurements(
        from measurements: [VideoClipAlignmentMeasurement]
    ) -> [VideoClipAlignmentMeasurement]? {
        var best: [VideoClipAlignmentMeasurement]?
        for model in [ClipAlignmentMotionModel.similarity, .translation] {
            let matching = measurements.filter { $0.model == model }
            guard matching.count >= 2 else { continue }
            for size in stride(from: matching.count, through: 2, by: -1) {
                for subset in combinations(of: matching, taking: size) {
                    let center = medianTransform(of: subset)
                    guard transformSpread(subset, around: center) <= 0.025,
                          intersect(subset.map(\.validRegion)) != nil else {
                        continue
                    }
                    if isBetterConsensus(subset, than: best) {
                        best = subset
                    }
                }
                if best?.count == size { break }
            }
        }
        return best
    }

    private func combinations(
        of measurements: [VideoClipAlignmentMeasurement],
        taking count: Int
    ) -> [[VideoClipAlignmentMeasurement]] {
        guard count > 0, count <= measurements.count else { return [] }
        if count == measurements.count { return [measurements] }
        if count == 1 { return measurements.map { [$0] } }
        var result: [[VideoClipAlignmentMeasurement]] = []
        for index in 0...(measurements.count - count) {
            let head = measurements[index]
            let tail = Array(measurements[(index + 1)...])
            for remainder in combinations(of: tail, taking: count - 1) {
                result.append([head] + remainder)
            }
        }
        return result
    }

    private func isBetterConsensus(
        _ candidate: [VideoClipAlignmentMeasurement],
        than current: [VideoClipAlignmentMeasurement]?
    ) -> Bool {
        guard let current else { return true }
        if candidate.count != current.count { return candidate.count > current.count }
        let candidateScore = candidate.map(\.quality.score).min() ?? 0
        let currentScore = current.map(\.quality.score).min() ?? 0
        if candidateScore != currentScore { return candidateScore > currentScore }
        return candidate.first?.model == .similarity && current.first?.model != .similarity
    }

    private func medianTransform(
        of measurements: [VideoClipAlignmentMeasurement]
    ) -> ClipAlignmentTransform {
        ClipAlignmentTransform(
            a: median(measurements.map(\.transform.a)),
            b: median(measurements.map(\.transform.b)),
            c: median(measurements.map(\.transform.c)),
            d: median(measurements.map(\.transform.d)),
            tx: median(measurements.map(\.transform.tx)),
            ty: median(measurements.map(\.transform.ty))
        )
    }

    private func logSample(
        _ measurement: VideoClipAlignmentMeasurement,
        fraction: Double,
        sourceIndex: Int
    ) {
        CameraeAlignmentDiagnostics.event(
            "analysis.sample",
            "source=\(sourceIndex) fraction=\(fraction) model=\(measurement.model.rawValue) decision=\(measurement.quality.decision.rawValue) score=\(measurement.quality.score) tx=\(measurement.transform.tx) ty=\(measurement.transform.ty) reasons=\(measurement.quality.reasonCodes.joined(separator: ","))"
        )
    }

    private func rejectedCandidate(itemID: UUID, reason: String) -> ClipAlignmentCandidate {
        ClipAlignmentCandidate(
            itemID: itemID,
            model: .translation,
            transform: .identity,
            validRegion: .full,
            quality: .init(decision: .reject, score: 0, reasonCodes: [reason])
        )
    }

    private func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    private func transformSpread(
        _ measurements: [VideoClipAlignmentMeasurement],
        around center: ClipAlignmentTransform
    ) -> Double {
        measurements.map {
            [
                abs($0.transform.a - center.a), abs($0.transform.b - center.b),
                abs($0.transform.c - center.c), abs($0.transform.d - center.d),
                abs($0.transform.tx - center.tx), abs($0.transform.ty - center.ty)
            ].max() ?? .infinity
        }.max() ?? .infinity
    }

    private func intersect(
        _ regions: [ClipAlignmentNormalizedRect]
    ) -> ClipAlignmentNormalizedRect? {
        guard var minimumX = regions.first?.x,
              var minimumY = regions.first?.y,
              var maximumX = regions.first.map({ $0.x + $0.width }),
              var maximumY = regions.first.map({ $0.y + $0.height }) else { return nil }
        for region in regions.dropFirst() {
            minimumX = max(minimumX, region.x)
            minimumY = max(minimumY, region.y)
            maximumX = min(maximumX, region.x + region.width)
            maximumY = min(maximumY, region.y + region.height)
        }
        guard maximumX > minimumX, maximumY > minimumY else { return nil }
        return .init(
            x: minimumX,
            y: minimumY,
            width: maximumX - minimumX,
            height: maximumY - minimumY
        )
    }
}

enum VideoClipAlignmentAnalysisError: Error, Equatable {
    case emptyTimeline
    case duplicateItem
    case invalidDuration
    case insufficientReferenceSamples
}
