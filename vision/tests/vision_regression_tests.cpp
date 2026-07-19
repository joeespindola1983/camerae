#include "camerae_vision/automatic_alignment.hpp"
#include "camerae_vision/capture_alignment_session.hpp"

#include <algorithm>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

#include <opencv2/core.hpp>
#include <opencv2/imgproc.hpp>

namespace {

using namespace camerae_vision;

void require(bool condition, const std::string& message) {
    if (!condition) throw std::runtime_error(message);
}

cv::Mat fixture() {
    cv::Mat image(480, 640, CV_8UC3);
    cv::RNG random(20260720);
    random.fill(image, cv::RNG::UNIFORM, 0, 255);
    cv::GaussianBlur(image, image, cv::Size(7, 7), 1.8);
    for (int row = 50; row < image.rows; row += 80) {
        for (int column = 50; column < image.cols; column += 95) {
            cv::rectangle(image, cv::Rect(column, row, 28, 22),
                          cv::Scalar(column % 255, row % 255, (row + column) % 255), 3);
        }
    }
    cv::putText(image, "REGRESSION", cv::Point(95, 440), cv::FONT_HERSHEY_SIMPLEX,
                1.2, cv::Scalar::all(250), 3, cv::LINE_AA);
    return image;
}

cv::Mat warp(const cv::Mat& reference, const cv::Mat& transform) {
    cv::Mat moving;
    cv::warpPerspective(reference, moving, transform, reference.size(), cv::INTER_LINEAR,
                        cv::BORDER_CONSTANT, cv::Scalar::all(0));
    return moving;
}

AutomaticAlignmentSettings settings() {
    AutomaticAlignmentSettings value;
    value.alignment.maxDimension = 0;
    value.alignment.maxFeatures = 4000;
    value.alignment.matchRatio = 0.85f;
    value.alignment.ransacThreshold = 2.0;
    return value;
}

void testSyntheticModelDataset() {
    const cv::Mat reference = fixture();
    cv::Mat similarityAffine = cv::getRotationMatrix2D(cv::Point2f(320, 240), 2.0, 1.02);
    cv::Mat similarity = cv::Mat::eye(3, 3, CV_64F);
    similarityAffine.copyTo(similarity(cv::Rect(0, 0, 3, 2)));
    struct Scenario {
        std::string name;
        cv::Mat transform;
        AlignmentMotionModel expectedModel;
    };
    const std::vector<Scenario> scenarios = {
        {"similarity", similarity, AlignmentMotionModel::Similarity},
        {"affine", (cv::Mat_<double>(3, 3) <<
            1.0, 0.12, -22.0, 0.03, 1.0, 7.0, 0.0, 0.0, 1.0), AlignmentMotionModel::Affine},
        {"perspective", (cv::Mat_<double>(3, 3) <<
            1.0, 0.02, -10.0, 0.01, 1.0, -6.0, 0.00035, 0.00016, 1.0),
            AlignmentMotionModel::Homography}
    };

    for (const auto& scenario : scenarios) {
        const auto result = alignImagesAutomatically(
            reference, warp(reference, scenario.transform), settings()
        );
        require(result.selectedModel == scenario.expectedModel,
                scenario.name + " selected an unexpected model");
        require(result.alignment.metrics.grayMAEAfter < result.alignment.metrics.grayMAEBefore,
                scenario.name + " should improve photometric alignment");
    }
}

void testMovingObjectDoesNotReceiveStableGeometry() {
    const cv::Mat reference = fixture();
    const cv::Mat transform = (cv::Mat_<double>(3, 3) <<
        1.0, 0.0, -8.0, 0.0, 1.0, 4.0, 0.0, 0.0, 1.0);
    cv::Mat moving = warp(reference, transform);
    cv::rectangle(moving, cv::Rect(170, 120, 300, 220), cv::Scalar::all(0), cv::FILLED);
    CaptureAlignmentSession session(reference);

    const auto quality = session.evaluate(moving);

    require(quality.has_value(), "moving-object scenario should produce diagnostics");
    require(quality->decision != AlignmentDecision::Accept,
            "large moving object should not receive stable-geometry acceptance");
    require(std::find(quality->reasonCodes.begin(), quality->reasonCodes.end(),
                      AlignmentReasonCode::StableGeometry) == quality->reasonCodes.end(),
            "moving-object scenario should not expose stableGeometry");
}

} // namespace

int main() {
    try {
        testSyntheticModelDataset();
        testMovingObjectDoesNotReceiveStableGeometry();
        std::cout << "camerae_vision_regression_tests passed\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "camerae_vision_regression_tests failed: " << error.what() << "\n";
        return 1;
    }
}
