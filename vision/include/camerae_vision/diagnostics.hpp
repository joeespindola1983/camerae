#pragma once

#include <string>

namespace camerae_vision {

inline constexpr int cameraeVisionDiagnosticsSchemaVersion = 1;

enum class AlignmentReasonCode {
    StableGeometry,
    InsufficientInliers,
    InconsistentMatches,
    InsufficientCoverage,
    InsufficientGridCoverage,
    InsufficientOverlap,
    HighReprojectionError,
    NonConvexProjection,
    ExtremeAreaChange,
    ExtremeEdgeScale,
    HighLocalResidual,
    ModerateMatchConsistency,
    PoorFrameCoverage,
    SparseGridCoverage,
    LargeCrop,
    RelevantAreaChange,
    PerceptibleEdgeDeformation,
    LargeFrameDisplacement,
    PossibleParallaxOrMotion,
    AnalysisFailure
};

std::string alignmentReasonCodeName(AlignmentReasonCode code);

} // namespace camerae_vision
