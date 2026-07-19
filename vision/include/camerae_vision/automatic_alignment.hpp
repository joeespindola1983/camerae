#pragma once

#include "camerae_vision/alignment.hpp"

#include <string>
#include <vector>

namespace camerae_vision {

struct AutomaticAlignmentSettings {
    AlignmentSettings alignment;
    double affineLocalErrorRatio = 0.85;
    double homographyLocalErrorRatio = 0.70;
};

struct AlignmentCandidateSummary {
    AlignmentMotionModel model = AlignmentMotionModel::Similarity;
    bool succeeded = false;
    AlignmentDecision decision = AlignmentDecision::Reject;
    double score = 0.0;
    double reprojectionRMSE = 0.0;
    double edgeAlignmentError = 0.0;
    std::string failureReason;
};

struct AutomaticAlignmentResult {
    AlignmentResult alignment;
    AlignmentMotionModel selectedModel = AlignmentMotionModel::Similarity;
    std::vector<AlignmentCandidateSummary> candidates;
};

AutomaticAlignmentResult alignImagesAutomatically(
    const cv::Mat& reference,
    const cv::Mat& moving,
    const AutomaticAlignmentSettings& settings = {}
);

} // namespace camerae_vision
