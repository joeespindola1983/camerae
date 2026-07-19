#include "camerae_vision/alignment_quality.hpp"

#include <iostream>
#include <stdexcept>
#include <string>

#include <opencv2/core.hpp>
#include <opencv2/imgproc.hpp>

namespace {

using namespace camerae_vision;

void require(bool condition, const std::string& message) {
    if (!condition) {
        throw std::runtime_error(message);
    }
}

cv::Mat makeFixture() {
    cv::Mat image(480, 640, CV_8UC3);
    cv::RNG random(20260720);
    random.fill(image, cv::RNG::UNIFORM, 0, 255);
    cv::GaussianBlur(image, image, cv::Size(5, 5), 0.8);
    for (int row = 60; row < image.rows; row += 90) {
        for (int column = 60; column < image.cols; column += 110) {
            cv::circle(image, cv::Point(column, row), 18,
                       cv::Scalar((row + column) % 255, column % 255, row % 255), 3);
        }
    }
    cv::putText(image, "CAPTURE FAST", cv::Point(90, 430), cv::FONT_HERSHEY_SIMPLEX,
                1.2, cv::Scalar::all(250), 3, cv::LINE_AA);
    return image;
}

cv::Mat warped(const cv::Mat& reference, const cv::Mat& referenceToMoving) {
    cv::Mat moving;
    cv::warpAffine(reference, moving, referenceToMoving, reference.size(), cv::INTER_LINEAR,
                   cv::BORDER_CONSTANT, cv::Scalar::all(0));
    return moving;
}

void testChoosesSimilarityWhenSufficient() {
    const cv::Mat reference = makeFixture();
    cv::Mat transform = cv::getRotationMatrix2D(cv::Point2f(320, 240), 2.0, 1.02);
    transform.at<double>(0, 2) += 8.0;
    transform.at<double>(1, 2) -= 5.0;

    AlignmentQualityEvaluator evaluator;
    const auto quality = evaluator.evaluate(reference, warped(reference, transform));

    require(quality.selectedModel == AlignmentMotionModel::Similarity,
            "captureFast should prefer similarity when it explains the motion");
    require(quality.transform.rows == 3 && quality.transform.cols == 3,
            "captureFast should expose the selected 3x3 transform to platform bridges");
    require(quality.decision != AlignmentDecision::Reject,
            "small similarity motion should remain correctable");
    require(quality.estimatedLatencyMilliseconds > 0.0,
            "captureFast should report measured evaluation latency");
}

void testChoosesAffineForMaterialImprovement() {
    const cv::Mat reference = makeFixture();
    const cv::Mat transform = (cv::Mat_<double>(2, 3) <<
        1.0, 0.10, -18.0,
        0.02, 1.0, 6.0
    );

    AlignmentQualityEvaluator evaluator;
    const auto quality = evaluator.evaluate(reference, warped(reference, transform));

    require(quality.selectedModel == AlignmentMotionModel::Affine,
            "captureFast should select affine when it materially reduces residual error; similarity=" +
                std::to_string(evaluator.diagnostics().similarityEdgeAlignmentError) + " affine=" +
                std::to_string(evaluator.diagnostics().affineEdgeAlignmentError));
}

void testRejectsExtremeTransform() {
    const cv::Mat reference = makeFixture();
    const cv::Mat transform = cv::getRotationMatrix2D(cv::Point2f(320, 240), 0.0, 0.30);

    AlignmentQualityEvaluator evaluator;
    const auto quality = evaluator.evaluate(reference, warped(reference, transform));

    require(quality.decision == AlignmentDecision::Reject,
            "captureFast should reject an extreme scale change");
    require(!quality.reasons.empty(), "rejection should include a reason");
}

void testFastPathDisablesExpensiveFeatures() {
    const cv::Mat reference = makeFixture();
    const cv::Mat transform = (cv::Mat_<double>(2, 3) << 1.0, 0.0, -10.0, 0.0, 1.0, 4.0);

    AlignmentQualityEvaluator evaluator;
    evaluator.evaluate(reference, warped(reference, transform));
    const auto diagnostics = evaluator.diagnostics();

    require(diagnostics.detector == AlignmentDetector::ORB, "captureFast must use ORB");
    require(!diagnostics.usedECC, "captureFast must not execute ECC");
    require(!diagnostics.usedSIFT, "captureFast must not execute SIFT");
}

void testReusesReferenceFeatures() {
    const cv::Mat reference = makeFixture();
    const cv::Mat first = (cv::Mat_<double>(2, 3) << 1.0, 0.0, -8.0, 0.0, 1.0, 3.0);
    const cv::Mat second = (cv::Mat_<double>(2, 3) << 1.0, 0.0, -12.0, 0.0, 1.0, 5.0);

    AlignmentQualityEvaluator evaluator;
    evaluator.evaluate(reference, warped(reference, first));
    evaluator.evaluate(reference, warped(reference, second));

    require(evaluator.diagnostics().referenceFeatureExtractions == 1,
            "unchanged reference and settings should reuse cached features");
}

void testInvalidatesCacheWhenReferenceChanges() {
    cv::Mat reference = makeFixture();
    const cv::Mat transform = (cv::Mat_<double>(2, 3) << 1.0, 0.0, -8.0, 0.0, 1.0, 3.0);

    AlignmentQualityEvaluator evaluator;
    evaluator.evaluate(reference, warped(reference, transform));
    cv::rectangle(reference, cv::Rect(0, 0, 80, 80), cv::Scalar::all(0), cv::FILLED);
    evaluator.evaluate(reference, warped(reference, transform));

    require(evaluator.diagnostics().referenceFeatureExtractions == 2,
            "changed reference pixels should invalidate cached features");
}

} // namespace

int main() {
    try {
        testChoosesSimilarityWhenSufficient();
        testChoosesAffineForMaterialImprovement();
        testRejectsExtremeTransform();
        testFastPathDisablesExpensiveFeatures();
        testReusesReferenceFeatures();
        testInvalidatesCacheWhenReferenceChanges();
        std::cout << "camerae_alignment_quality_tests passed\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "camerae_alignment_quality_tests failed: " << error.what() << "\n";
        return 1;
    }
}
