#include "camerae_vision/capture_alignment_session.hpp"

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

cv::Mat makeFixture(int seed = 20260720) {
    cv::Mat image(360, 480, CV_8UC3);
    cv::RNG random(seed);
    random.fill(image, cv::RNG::UNIFORM, 0, 255);
    cv::GaussianBlur(image, image, cv::Size(5, 5), 0.9);
    cv::putText(image, "SESSION", cv::Point(80, 290), cv::FONT_HERSHEY_SIMPLEX,
                1.2, cv::Scalar::all(250), 3, cv::LINE_AA);
    return image;
}

cv::Mat translated(const cv::Mat& reference, double x, double y) {
    const cv::Mat transform = (cv::Mat_<double>(2, 3) << 1.0, 0.0, -x, 0.0, 1.0, -y);
    cv::Mat moving;
    cv::warpAffine(reference, moving, transform, reference.size(), cv::INTER_LINEAR,
                   cv::BORDER_CONSTANT, cv::Scalar::all(0));
    return moving;
}

void testMultipleFramesReusePreparedReference() {
    const cv::Mat reference = makeFixture();
    CaptureAlignmentSession session(reference);

    require(session.evaluate(translated(reference, 6.0, -3.0)).has_value(),
            "session should evaluate the first frame");
    require(session.evaluate(translated(reference, 10.0, -5.0)).has_value(),
            "session should evaluate subsequent frames");

    const auto diagnostics = session.diagnostics();
    require(diagnostics.completedEvaluations == 2, "session should count completed evaluations");
    require(diagnostics.referenceFeatureExtractions == 1,
            "multiple frames should reuse one prepared reference");
}

void testReferenceUpdateInvalidatesPreparation() {
    const cv::Mat firstReference = makeFixture();
    const cv::Mat secondReference = makeFixture(20260721);
    CaptureAlignmentSession session(firstReference);

    session.evaluate(translated(firstReference, 6.0, -3.0));
    session.updateReference(secondReference);
    session.evaluate(translated(secondReference, 6.0, -3.0));

    const auto diagnostics = session.diagnostics();
    require(diagnostics.referenceUpdates == 1, "explicit reference changes should be counted");
    require(diagnostics.referenceFeatureExtractions == 2,
            "updated reference should trigger one new feature extraction");
}

void testCancellationSkipsEvaluationWithoutInspectingFrame() {
    CaptureAlignmentSession session(makeFixture());
    session.cancel();

    const auto result = session.evaluate(cv::Mat{});

    require(!result.has_value(), "cancelled session should return no result");
    require(session.diagnostics().completedEvaluations == 0,
            "cancelled session should not execute OpenCV work");
    require(session.diagnostics().cancelledEvaluations == 1,
            "cancelled submissions should be counted");
}

void testResumeRestoresEvaluation() {
    const cv::Mat reference = makeFixture();
    CaptureAlignmentSession session(reference);
    session.cancel();
    session.resume();

    require(session.evaluate(translated(reference, 4.0, 2.0)).has_value(),
            "resumed session should evaluate frames again");
}

void testRetainedReferenceMemoryIsBoundedAndReported() {
    const cv::Mat reference = makeFixture();
    CaptureAlignmentSession session(reference);
    session.evaluate(translated(reference, 4.0, 2.0));
    const auto diagnostics = session.diagnostics();
    const std::size_t referenceBytes = reference.total() * reference.elemSize();

    require(diagnostics.retainedReferenceBytes == referenceBytes,
            "session should report exactly one retained reference image");
    require(diagnostics.estimatedRetainedBytes >= referenceBytes,
            "estimated retained memory should include the prepared feature cache");
    require(diagnostics.estimatedRetainedBytes <= referenceBytes + 5 * 1024 * 1024,
            "prepared reference cache should remain bounded");
}

} // namespace

int main() {
    try {
        testMultipleFramesReusePreparedReference();
        testReferenceUpdateInvalidatesPreparation();
        testCancellationSkipsEvaluationWithoutInspectingFrame();
        testResumeRestoresEvaluation();
        testRetainedReferenceMemoryIsBoundedAndReported();
        std::cout << "camerae_capture_alignment_session_tests passed\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "camerae_capture_alignment_session_tests failed: " << error.what() << "\n";
        return 1;
    }
}
