#include "camerae_vision/capture_support.hpp"

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
    cv::Mat image(360, 480, CV_8UC3);
    cv::RNG random(20260720);
    random.fill(image, cv::RNG::UNIFORM, 0, 255);
    cv::GaussianBlur(image, image, cv::Size(5, 5), 0.8);
    cv::putText(image, "SUPPORT", cv::Point(90, 280), cv::FONT_HERSHEY_SIMPLEX,
                1.2, cv::Scalar::all(250), 3, cv::LINE_AA);
    return image;
}

cv::Mat translated(const cv::Mat& reference) {
    const cv::Mat transform = (cv::Mat_<double>(2, 3) <<
        1.0, 0.0, -8.0,
        0.0, 1.0, 4.0
    );
    cv::Mat moving;
    cv::warpAffine(reference, moving, transform, reference.size(), cv::INTER_LINEAR,
                   cv::BORDER_CONSTANT, cv::Scalar::all(0));
    return moving;
}

void testAlignmentSupportIsDisabledByDefault() {
    const CaptureSupportSettings settings;

    require(settings.id == CaptureSupportComponentID::AlignmentQuality,
            "capture support should identify alignment quality explicitly");
    require(!settings.enabled, "capture support must be disabled by default");
    require(settings.cadence == CaptureSupportCadence::Balanced,
            "balanced should be the neutral stored cadence");
}

void testDisabledSupportDoesNotCreateOrScheduleWork() {
    AlignmentQualityCaptureSupport support(CaptureSupportSettings{});

    const auto result = support.evaluateIfEnabled(cv::Mat{}, cv::Mat{});
    const auto diagnostics = support.diagnostics();

    require(!result.has_value(), "disabled support should return no evaluation");
    require(diagnostics.evaluatorInstancesCreated == 0,
            "disabled support should not construct an OpenCV evaluator");
    require(diagnostics.scheduledEvaluations == 0,
            "disabled support should not schedule work");
}

void testEnabledSupportCreatesEvaluatorLazilyAndReusesIt() {
    CaptureSupportSettings settings;
    settings.enabled = true;
    const cv::Mat reference = makeFixture();
    const cv::Mat moving = translated(reference);
    AlignmentQualityCaptureSupport support(settings);

    require(support.diagnostics().evaluatorInstancesCreated == 0,
            "enabled support should remain lazy until the first frame");
    require(support.evaluateIfEnabled(reference, moving).has_value(),
            "enabled support should evaluate a frame");
    require(support.evaluateIfEnabled(reference, moving).has_value(),
            "enabled support should evaluate subsequent frames");
    require(support.diagnostics().evaluatorInstancesCreated == 1,
            "enabled support should reuse one evaluator and its reference cache");
    require(support.diagnostics().scheduledEvaluations == 2,
            "enabled support should count scheduled evaluations");
}

void testCadencePoliciesHaveStableRates() {
    require(captureSupportAnalysisFPS(CaptureSupportCadence::Conservative) == 1.0,
            "conservative cadence should request 1 Hz");
    require(captureSupportAnalysisFPS(CaptureSupportCadence::Balanced) == 2.0,
            "balanced cadence should request 2 Hz");
    require(captureSupportAnalysisFPS(CaptureSupportCadence::Responsive) == 4.0,
            "responsive cadence should request 4 Hz");
}

} // namespace

int main() {
    try {
        testAlignmentSupportIsDisabledByDefault();
        testDisabledSupportDoesNotCreateOrScheduleWork();
        testEnabledSupportCreatesEvaluatorLazilyAndReusesIt();
        testCadencePoliciesHaveStableRates();
        std::cout << "camerae_capture_support_tests passed\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "camerae_capture_support_tests failed: " << error.what() << "\n";
        return 1;
    }
}
