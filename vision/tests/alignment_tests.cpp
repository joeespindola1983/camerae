#include "camerae_vision/alignment.hpp"

#include <cmath>
#include <iostream>
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

cv::Mat makeAlignmentFixture() {
    cv::Mat image(480, 640, CV_8UC3);
    cv::RNG random(20260719);
    random.fill(image, cv::RNG::UNIFORM, 0, 255);
    cv::GaussianBlur(image, image, cv::Size(5, 5), 0.8);
    cv::circle(image, cv::Point(150, 130), 55, cv::Scalar(20, 240, 100), 5);
    cv::rectangle(image, cv::Rect(360, 230, 140, 100), cv::Scalar(240, 80, 20), 6);
    cv::putText(image, "CAMERAE", cv::Point(120, 410), cv::FONT_HERSHEY_SIMPLEX,
                1.4, cv::Scalar(250, 250, 250), 3, cv::LINE_AA);
    return image;
}

camerae_vision::AlignmentSettings translationSettings() {
    camerae_vision::AlignmentSettings settings;
    settings.motionModel = camerae_vision::AlignmentMotionModel::Translation;
    settings.maxDimension = 0;
    settings.maxFeatures = 3000;
    settings.matchRatio = 0.85f;
    settings.mutualMatching = true;
    settings.ransacThreshold = 2.0;
    return settings;
}

cv::Mat translatedFixture(const cv::Mat& reference, double horizontalOffset) {
    const cv::Mat referenceToMoving = (cv::Mat_<double>(2, 3) <<
        1.0, 0.0, -horizontalOffset,
        0.0, 1.0, 0.0
    );
    cv::Mat moving;
    cv::warpAffine(reference, moving, referenceToMoving, reference.size(), cv::INTER_LINEAR,
                   cv::BORDER_CONSTANT, cv::Scalar::all(0));
    return moving;
}

void testAlignmentParsing() {
    using namespace camerae_vision;
    requireAlignment(parseAlignmentDetector("AKAZE") == AlignmentDetector::AKAZE,
                     "alignment detector parsing should be case insensitive");
    requireAlignment(parseAlignmentMotionModel("homografia") == AlignmentMotionModel::Homography,
                     "Portuguese homography alias should work");
    requireAlignment(alignmentMotionModelName(AlignmentMotionModel::Similarity) == "similarity",
                     "alignment model name should be stable");
}

void testSyntheticTranslation() {
    using namespace camerae_vision;

    const cv::Mat reference = makeAlignmentFixture();

    const cv::Mat referenceToMoving = (cv::Mat_<double>(2, 3) <<
        1.0, 0.0, -12.0,
        0.0, 1.0, 8.0
    );
    cv::Mat moving;
    cv::warpAffine(reference, moving, referenceToMoving, reference.size(), cv::INTER_LINEAR,
                   cv::BORDER_CONSTANT, cv::Scalar::all(0));

    const AlignmentSettings settings = translationSettings();

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

void testSyntheticReviewDecision() {
    using namespace camerae_vision;

    const cv::Mat reference = makeAlignmentFixture();
    const cv::Mat moving = translatedFixture(reference, 160.0);
    const AlignmentResult result = alignImages(reference, moving, translationSettings());

    requireAlignment(result.metrics.overlapRatio >= 0.55 && result.metrics.overlapRatio < 0.80,
                     "review fixture should retain a usable but cropped overlap");
    requireAlignment(result.feasibility.decision == AlignmentDecision::Review,
                     "large but correctable translation should require review");
    requireAlignment(!result.feasibility.reasons.empty(),
                     "review decision should explain the quality concern");
}

void testSyntheticRejectDecision() {
    using namespace camerae_vision;

    const cv::Mat reference = makeAlignmentFixture();
    const cv::Mat moving = translatedFixture(reference, 320.0);
    const AlignmentResult result = alignImages(reference, moving, translationSettings());

    requireAlignment(result.metrics.overlapRatio < 0.55,
                     "reject fixture should leave less than the minimum usable overlap");
    requireAlignment(result.feasibility.decision == AlignmentDecision::Reject,
                     "extreme translation should fail the feasibility gate");
    requireAlignment(!result.feasibility.reasons.empty(),
                     "reject decision should explain the hard failure");
}

} // namespace

int main() {
    try {
        testAlignmentParsing();
        testSyntheticTranslation();
        testSyntheticReviewDecision();
        testSyntheticRejectDecision();
        std::cout << "camerae_vision_tests passed\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "camerae_vision_tests failed: " << error.what() << "\n";
        return 1;
    }
}
