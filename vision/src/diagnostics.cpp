#include "camerae_vision/diagnostics.hpp"

namespace camerae_vision {

std::string alignmentReasonCodeName(AlignmentReasonCode code) {
    switch (code) {
    case AlignmentReasonCode::StableGeometry: return "stableGeometry";
    case AlignmentReasonCode::InsufficientInliers: return "insufficientInliers";
    case AlignmentReasonCode::InconsistentMatches: return "inconsistentMatches";
    case AlignmentReasonCode::InsufficientCoverage: return "insufficientCoverage";
    case AlignmentReasonCode::InsufficientGridCoverage: return "insufficientGridCoverage";
    case AlignmentReasonCode::InsufficientOverlap: return "insufficientOverlap";
    case AlignmentReasonCode::HighReprojectionError: return "highReprojectionError";
    case AlignmentReasonCode::NonConvexProjection: return "nonConvexProjection";
    case AlignmentReasonCode::ExtremeAreaChange: return "extremeAreaChange";
    case AlignmentReasonCode::ExtremeEdgeScale: return "extremeEdgeScale";
    case AlignmentReasonCode::HighLocalResidual: return "highLocalResidual";
    case AlignmentReasonCode::ModerateMatchConsistency: return "moderateMatchConsistency";
    case AlignmentReasonCode::PoorFrameCoverage: return "poorFrameCoverage";
    case AlignmentReasonCode::SparseGridCoverage: return "sparseGridCoverage";
    case AlignmentReasonCode::LargeCrop: return "largeCrop";
    case AlignmentReasonCode::RelevantAreaChange: return "relevantAreaChange";
    case AlignmentReasonCode::PerceptibleEdgeDeformation: return "perceptibleEdgeDeformation";
    case AlignmentReasonCode::LargeFrameDisplacement: return "largeFrameDisplacement";
    case AlignmentReasonCode::PossibleParallaxOrMotion: return "possibleParallaxOrMotion";
    case AlignmentReasonCode::AnalysisFailure: return "analysisFailure";
    }
    return "unknown";
}

} // namespace camerae_vision
