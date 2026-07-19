#include "camerae_vision/automatic_alignment.hpp"

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

std::string candidateErrors(const AutomaticAlignmentResult& result) {
    std::string output;
    for (const auto& candidate : result.candidates) {
        output += alignmentMotionModelName(candidate.model) + "=" +
            std::to_string(candidate.edgeAlignmentError) + " ";
    }
    return output;
}

cv::Mat makeFixture() {
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
    cv::putText(image, "FINAL AUTO", cv::Point(120, 440), cv::FONT_HERSHEY_SIMPLEX,
                1.25, cv::Scalar::all(250), 3, cv::LINE_AA);
    return image;
}

cv::Mat warped(const cv::Mat& reference, const cv::Mat& transform) {
    cv::Mat moving;
    cv::warpPerspective(reference, moving, transform, reference.size(), cv::INTER_LINEAR,
                        cv::BORDER_CONSTANT, cv::Scalar::all(0));
    return moving;
}

AutomaticAlignmentSettings automaticSettings() {
    AutomaticAlignmentSettings settings;
    settings.alignment.maxDimension = 0;
    settings.alignment.maxFeatures = 4000;
    settings.alignment.matchRatio = 0.85f;
    settings.alignment.mutualMatching = true;
    settings.alignment.ransacThreshold = 2.0;
    return settings;
}

void testPrefersSimilarityForRigidMotion() {
    const cv::Mat reference = makeFixture();
    cv::Mat affine = cv::getRotationMatrix2D(cv::Point2f(320, 240), 2.0, 1.02);
    affine.at<double>(0, 2) += 8.0;
    affine.at<double>(1, 2) -= 5.0;
    cv::Mat transform = cv::Mat::eye(3, 3, CV_64F);
    affine.copyTo(transform(cv::Rect(0, 0, 3, 2)));

    const auto result = alignImagesAutomatically(
        reference, warped(reference, transform), automaticSettings()
    );

    require(result.selectedModel == AlignmentMotionModel::Similarity,
            "automatic final alignment should keep similarity for rigid motion");
    require(result.candidates.size() == 3, "all three final models should be diagnosed");
}

void testSelectsAffineForShear() {
    const cv::Mat reference = makeFixture();
    const cv::Mat transform = (cv::Mat_<double>(3, 3) <<
        1.0, 0.12, -22.0,
        0.03, 1.0, 7.0,
        0.0, 0.0, 1.0
    );

    const auto result = alignImagesAutomatically(
        reference, warped(reference, transform), automaticSettings()
    );

    require(result.selectedModel == AlignmentMotionModel::Affine,
            "automatic final alignment should promote material shear to affine");
}

void testSelectsHomographyForPerspective() {
    const cv::Mat reference = makeFixture();
    const cv::Mat transform = (cv::Mat_<double>(3, 3) <<
        1.0, 0.02, -10.0,
        0.01, 1.0, -6.0,
        0.00035, 0.00016, 1.0
    );

    const auto result = alignImagesAutomatically(
        reference, warped(reference, transform), automaticSettings()
    );

    require(result.selectedModel == AlignmentMotionModel::Homography,
            "automatic final alignment should use homography for real perspective; " +
                candidateErrors(result));
}

void testExplicitAlignmentAPIStillUsesRequestedModel() {
    const cv::Mat reference = makeFixture();
    const cv::Mat transform = (cv::Mat_<double>(3, 3) <<
        1.0, 0.08, -16.0,
        0.02, 1.0, 5.0,
        0.0, 0.0, 1.0
    );
    AlignmentSettings settings = automaticSettings().alignment;
    settings.motionModel = AlignmentMotionModel::Similarity;

    const auto result = alignImages(reference, warped(reference, transform), settings);

    require(result.transform.rows == 3 && result.transform.cols == 3,
            "explicit alignment should remain available and return its requested transform");
}

} // namespace

int main() {
    try {
        testPrefersSimilarityForRigidMotion();
        testSelectsAffineForShear();
        testSelectsHomographyForPerspective();
        testExplicitAlignmentAPIStillUsesRequestedModel();
        std::cout << "camerae_automatic_alignment_tests passed\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "camerae_automatic_alignment_tests failed: " << error.what() << "\n";
        return 1;
    }
}
