import Foundation

public enum ClipAlignmentMotionModel: String, Codable, Equatable, Sendable {
    case identity
    case translation
    case similarity
    case affine
    case perspective
}

public enum ClipAlignmentDecision: String, Codable, Equatable, Sendable {
    case apply
    case review
    case reject
}

public struct ClipAlignmentTransform: Codable, Equatable, Sendable {
    public let a: Double
    public let b: Double
    public let c: Double
    public let d: Double
    public let tx: Double
    public let ty: Double

    public static let identity = Self(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0)

    public init(a: Double, b: Double, c: Double, d: Double, tx: Double, ty: Double) {
        self.a = a
        self.b = b
        self.c = c
        self.d = d
        self.tx = tx
        self.ty = ty
    }

    public static func similarity(
        translationX: Double,
        translationY: Double,
        rotationRadians: Double,
        scale: Double
    ) -> Self {
        let cosine = cos(rotationRadians) * scale
        let sine = sin(rotationRadians) * scale
        let center = 0.5
        return Self(
            a: cosine,
            b: sine,
            c: -sine,
            d: cosine,
            tx: center + translationX - cosine * center + sine * center,
            ty: center + translationY - sine * center - cosine * center
        )
    }

    public var isFinite: Bool {
        [a, b, c, d, tx, ty].allSatisfy(\.isFinite)
    }
}

public struct ClipAlignmentNormalizedRect: Codable, Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public static let full = Self(x: 0, y: 0, width: 1, height: 1)

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var area: Double { width * height }

    fileprivate var isValid: Bool {
        [x, y, width, height].allSatisfy(\.isFinite) &&
            x >= 0 && y >= 0 && width > 0 && height > 0 &&
            x + width <= 1.000_000_1 && y + height <= 1.000_000_1
    }

    fileprivate func intersection(_ other: Self) -> Self? {
        let minimumX = max(x, other.x)
        let minimumY = max(y, other.y)
        let maximumX = min(x + width, other.x + other.width)
        let maximumY = min(y + height, other.y + other.height)
        guard maximumX > minimumX, maximumY > minimumY else { return nil }
        return Self(
            x: minimumX,
            y: minimumY,
            width: maximumX - minimumX,
            height: maximumY - minimumY
        )
    }
}

public struct ClipAlignmentQuality: Codable, Equatable, Sendable {
    public let decision: ClipAlignmentDecision
    public let score: Double
    public let reasonCodes: [String]

    public init(decision: ClipAlignmentDecision, score: Double, reasonCodes: [String]) {
        self.decision = decision
        self.score = score
        self.reasonCodes = reasonCodes
    }
}

public struct ClipAlignmentCandidate: Codable, Equatable, Sendable {
    public let itemID: UUID
    public let model: ClipAlignmentMotionModel
    public let transform: ClipAlignmentTransform
    public let validRegion: ClipAlignmentNormalizedRect
    public let quality: ClipAlignmentQuality

    public init(
        itemID: UUID,
        model: ClipAlignmentMotionModel,
        transform: ClipAlignmentTransform,
        validRegion: ClipAlignmentNormalizedRect,
        quality: ClipAlignmentQuality
    ) {
        self.itemID = itemID
        self.model = model
        self.transform = transform
        self.validRegion = validRegion
        self.quality = quality
    }

    public static func identity(itemID: UUID) -> Self {
        Self(
            itemID: itemID,
            model: .identity,
            transform: .identity,
            validRegion: .full,
            quality: .init(decision: .apply, score: 1, reasonCodes: ["referenceIdentity"])
        )
    }
}

public struct EditSpatialAlignmentPlan: Codable, Equatable, Sendable {
    public let referenceItemID: UUID
    public let corrections: [UUID: ClipAlignmentCandidate]
    public let commonCrop: ClipAlignmentNormalizedRect
    public let decision: ClipAlignmentDecision
    public let reasonCodes: [String]

    public var applicableCorrections: [UUID: ClipAlignmentCandidate] {
        decision == .apply ? corrections : [:]
    }
}

public struct ClipSpatialAlignmentPlanner: Sendable {
    public let maximumCropFraction: Double

    public init(maximumCropFraction: Double = 0.20) {
        self.maximumCropFraction = maximumCropFraction
    }

    public func makePlan(
        referenceItemID: UUID,
        candidates: [ClipAlignmentCandidate]
    ) throws -> EditSpatialAlignmentPlan {
        guard maximumCropFraction.isFinite,
              maximumCropFraction >= 0,
              maximumCropFraction < 1 else {
            throw ClipSpatialAlignmentError.invalidCropLimit
        }
        guard candidates.contains(where: { $0.itemID == referenceItemID }) else {
            throw ClipSpatialAlignmentError.missingReference(referenceItemID)
        }

        var corrections: [UUID: ClipAlignmentCandidate] = [:]
        var commonCrop = ClipAlignmentNormalizedRect.full
        var reasons: [String] = []
        var decision = ClipAlignmentDecision.apply

        for candidate in candidates {
            guard corrections[candidate.itemID] == nil else {
                throw ClipSpatialAlignmentError.duplicateItem(candidate.itemID)
            }
            guard candidate.transform.isFinite else {
                throw ClipSpatialAlignmentError.invalidTransform(candidate.itemID)
            }
            guard candidate.validRegion.isValid,
                  let intersection = commonCrop.intersection(candidate.validRegion) else {
                throw ClipSpatialAlignmentError.invalidValidRegion(candidate.itemID)
            }
            guard candidate.quality.score.isFinite,
                  (0...1).contains(candidate.quality.score) else {
                throw ClipSpatialAlignmentError.invalidQuality(candidate.itemID)
            }

            commonCrop = intersection
            corrections[candidate.itemID] = candidate
            reasons.append(contentsOf: candidate.quality.reasonCodes)
            if candidate.quality.decision == .reject {
                decision = .reject
            } else if decision != .reject,
                      candidate.quality.decision == .review {
                decision = .review
            }
            if decision == .apply,
               candidate.model == .affine || candidate.model == .perspective {
                decision = .review
                reasons.append("deformationRequiresReview")
            }
        }

        if 1 - commonCrop.area > maximumCropFraction {
            decision = .reject
            reasons.append("excessiveCommonCrop")
        }

        return EditSpatialAlignmentPlan(
            referenceItemID: referenceItemID,
            corrections: corrections,
            commonCrop: commonCrop,
            decision: decision,
            reasonCodes: Array(Set(reasons)).sorted()
        )
    }
}

public enum ClipSpatialAlignmentError: Error, Equatable {
    case invalidCropLimit
    case missingReference(UUID)
    case duplicateItem(UUID)
    case invalidTransform(UUID)
    case invalidValidRegion(UUID)
    case invalidQuality(UUID)
}
