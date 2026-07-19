#pragma once

#include <string>
#include <vector>

#include <opencv2/core.hpp>

namespace camerae_processing {

enum class AlignmentDetector {
    ORB,
    AKAZE,
    SIFT
};

enum class AlignmentMotionModel {
    Translation,
    Similarity,
    Affine,
    Homography
};

enum class AlignmentDecision {
    Accept,
    Review,
    Reject
};

struct AlignmentSettings {
    AlignmentDetector detector = AlignmentDetector::ORB;
    AlignmentMotionModel motionModel = AlignmentMotionModel::Homography;
    int maxDimension = 1920;
    int maxFeatures = 6000;
    float matchRatio = 0.78f;
    bool mutualMatching = true;
    bool useCLAHE = false;
    double ransacThreshold = 3.0;
    int ransacMaxIterations = 4000;
    double ransacConfidence = 0.995;
    bool refineWithECC = false;
    int eccIterations = 60;
    double eccEpsilon = 1e-5;
};

struct AlignmentMetrics {
    int referenceKeypoints = 0;
    int movingKeypoints = 0;
    int candidateMatches = 0;
    int inlierMatches = 0;
    double inlierRatio = 0.0;
    double reprojectionRMSE = 0.0;
    double overlapRatio = 0.0;
    double grayMAEBefore = 0.0;
    double grayMAEAfter = 0.0;
    double eccCorrelation = 0.0;
    double inlierCoverageRatio = 0.0;
    double inlierGridCoverageRatio = 0.0;
    double projectedAreaRatio = 0.0;
    double minimumEdgeScale = 0.0;
    double maximumEdgeScale = 0.0;
    double maximumCornerDisplacementRatio = 0.0;
    double edgeAlignmentError = 0.0;
};

struct AlignmentFeasibility {
    AlignmentDecision decision = AlignmentDecision::Reject;
    double score = 0.0;
    std::vector<std::string> reasons;
};

struct AlignmentResult {
    cv::Mat alignedImage;
    cv::Mat validMask;
    cv::Mat transform;
    cv::Mat matchVisualization;
    AlignmentMetrics metrics;
    AlignmentFeasibility feasibility;
};

AlignmentResult alignImages(
    const cv::Mat& reference,
    const cv::Mat& moving,
    const AlignmentSettings& settings = {}
);

cv::Mat makeAlignmentOverlay(
    const cv::Mat& reference,
    const cv::Mat& aligned,
    const cv::Mat& validMask,
    double movingOpacity = 0.5
);

cv::Mat makeAlignmentDifference(
    const cv::Mat& reference,
    const cv::Mat& aligned,
    const cv::Mat& validMask
);

cv::Mat makeAlignmentRedCyan(
    const cv::Mat& reference,
    const cv::Mat& aligned,
    const cv::Mat& validMask
);

AlignmentDetector parseAlignmentDetector(const std::string& value);
AlignmentMotionModel parseAlignmentMotionModel(const std::string& value);
std::string alignmentDetectorName(AlignmentDetector detector);
std::string alignmentMotionModelName(AlignmentMotionModel motionModel);
std::string alignmentDecisionName(AlignmentDecision decision);

} // namespace camerae_processing
