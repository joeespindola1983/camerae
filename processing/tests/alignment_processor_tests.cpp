#include "camerae_processing/alignment_processor.hpp"

#include <cmath>
#include <stdexcept>
#include <string>

#include <opencv2/core.hpp>
#include <opencv2/imgproc.hpp>

namespace {

void requireAlignment(bool condition, const std::string& message) {
    if (!condition) {
        throw std::runtime_error(message);
    }
}

void testAlignmentParsing() {
    using namespace camerae_processing;
    requireAlignment(parseAlignmentDetector("AKAZE") == AlignmentDetector::AKAZE,
                     "alignment detector parsing should be case insensitive");
    requireAlignment(parseAlignmentMotionModel("homografia") == AlignmentMotionModel::Homography,
                     "Portuguese homography alias should work");
    requireAlignment(alignmentMotionModelName(AlignmentMotionModel::Similarity) == "similarity",
                     "alignment model name should be stable");
}

void testSyntheticTranslation() {
    using namespace camerae_processing;

    cv::Mat reference(360, 480, CV_8UC3);
    cv::RNG random(20260719);
    random.fill(reference, cv::RNG::UNIFORM, 0, 255);
    cv::GaussianBlur(reference, reference, cv::Size(5, 5), 0.8);
    cv::circle(reference, cv::Point(130, 110), 45, cv::Scalar(20, 240, 100), 5);
    cv::rectangle(reference, cv::Rect(260, 190, 110, 80), cv::Scalar(240, 80, 20), 6);
    cv::putText(reference, "CAMERAE", cv::Point(80, 310), cv::FONT_HERSHEY_SIMPLEX,
                1.2, cv::Scalar(250, 250, 250), 3, cv::LINE_AA);

    const cv::Mat referenceToMoving = (cv::Mat_<double>(2, 3) <<
        1.0, 0.0, -12.0,
        0.0, 1.0, 8.0
    );
    cv::Mat moving;
    cv::warpAffine(reference, moving, referenceToMoving, reference.size(), cv::INTER_LINEAR,
                   cv::BORDER_CONSTANT, cv::Scalar::all(0));

    AlignmentSettings settings;
    settings.motionModel = AlignmentMotionModel::Translation;
    settings.maxDimension = 0;
    settings.maxFeatures = 2500;
    settings.matchRatio = 0.85f;
    settings.mutualMatching = true;
    settings.ransacThreshold = 2.0;

    const AlignmentResult result = alignImages(reference, moving, settings);
    requireAlignment(result.metrics.inlierMatches >= 20,
                     "synthetic alignment should retain enough inliers");
    requireAlignment(std::abs(result.transform.at<double>(0, 2) - 12.0) < 1.0,
                     "synthetic horizontal translation should be recovered");
    requireAlignment(std::abs(result.transform.at<double>(1, 2) + 8.0) < 1.0,
                     "synthetic vertical translation should be recovered");
    requireAlignment(result.metrics.grayMAEAfter < result.metrics.grayMAEBefore * 0.25,
                     "alignment should materially reduce photometric error");
    requireAlignment(result.feasibility.decision == AlignmentDecision::Accept,
                     "clean synthetic translation should pass the feasibility gate");
}

} // namespace

void runAlignmentProcessorTests() {
    testAlignmentParsing();
    testSyntheticTranslation();
}
