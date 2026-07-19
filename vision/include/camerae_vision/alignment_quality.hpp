#pragma once

#include "camerae_vision/alignment.hpp"

#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

#include <opencv2/core.hpp>
#include <opencv2/features2d.hpp>

namespace camerae_vision {

enum class AlignmentQualityPreset {
    CaptureFast
};

struct CaptureAlignmentQuality {
    AlignmentDecision decision = AlignmentDecision::Reject;
    double score = 0.0;
    double overlapRatio = 0.0;
    double reprojectionRMSE = 0.0;
    double edgeAlignmentError = 0.0;
    double estimatedLatencyMilliseconds = 0.0;
    AlignmentMotionModel selectedModel = AlignmentMotionModel::Similarity;
    std::vector<std::string> reasons;
};

struct AlignmentQualityDiagnostics {
    AlignmentDetector detector = AlignmentDetector::ORB;
    bool usedECC = false;
    bool usedSIFT = false;
    std::size_t referenceFeatureExtractions = 0;
    std::size_t estimatedReferenceCacheBytes = 0;
    double similarityRMSE = 0.0;
    double affineRMSE = 0.0;
    double similarityEdgeAlignmentError = 0.0;
    double affineEdgeAlignmentError = 0.0;
};

class AlignmentQualityEvaluator {
public:
    explicit AlignmentQualityEvaluator(
        AlignmentQualityPreset preset = AlignmentQualityPreset::CaptureFast
    );

    CaptureAlignmentQuality evaluate(const cv::Mat& reference, const cv::Mat& moving);
    const AlignmentQualityDiagnostics& diagnostics() const;
    void resetReference();

private:
    AlignmentQualityPreset preset_;
    std::uint64_t referenceSignature_ = 0;
    bool hasReference_ = false;
    cv::Mat referenceGray_;
    std::vector<cv::KeyPoint> referenceKeypoints_;
    cv::Mat referenceDescriptors_;
    AlignmentQualityDiagnostics diagnostics_;
};

} // namespace camerae_vision
