#include "camerae_processing/astro_processor.hpp"

#include <chrono>
#include <filesystem>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

#include <opencv2/core.hpp>
#include <opencv2/imgcodecs.hpp>

namespace {

void require(bool condition, const std::string& message) {
    if (!condition) {
        throw std::runtime_error(message);
    }
}

template <typename Function>
void requireThrows(Function function, const std::string& message) {
    try {
        function();
    } catch (const std::exception&) {
        return;
    }
    throw std::runtime_error(message);
}

camerae_processing::AstroSettings neutralSettings() {
    camerae_processing::AstroSettings settings;
    settings.stackSize = 2;
    settings.maxDimension = 0;
    settings.alignStars = false;
    settings.denoise = false;
    settings.contrast = 1.0f;
    settings.brightness = 0.0f;
    settings.saturation = 1.0f;
    settings.gamma = 1.0f;
    return settings;
}

bool cancelImmediately(int, int, void*) {
    return false;
}

void testProfiles() {
    using namespace camerae_processing;
    require(parseProfile("NATURAL") == AstroProfile::Natural, "natural profile should be case insensitive");
    require(parseProfile("via-lactea") == AstroProfile::MilkyWay, "Portuguese milky-way alias should work");
    require(profileName(AstroProfile::Strong) == "strong", "strong profile name should be stable");
    requireThrows([] { parseProfile("unknown"); }, "unknown profile should throw");
}

void testSyntheticAverage(const std::filesystem::path& root) {
    using namespace camerae_processing;
    const auto first = root / "frame_000001.png";
    const auto second = root / "frame_000002.png";
    const auto output = root / "average.png";
    cv::imwrite(first.string(), cv::Mat(8, 8, CV_8UC3, cv::Scalar(10, 10, 10)));
    cv::imwrite(second.string(), cv::Mat(8, 8, CV_8UC3, cv::Scalar(30, 30, 30)));

    const auto result = renderAstroStack({first, second}, output, neutralSettings());
    const cv::Mat image = cv::imread(output.string(), cv::IMREAD_COLOR);

    require(result.discoveredFrames == 2, "two frames should be discovered");
    require(result.usedFrames == 2, "two frames should be used");
    require(!image.empty(), "output should be readable");
    require(cv::norm(image, cv::Mat(8, 8, CV_8UC3, cv::Scalar(20, 20, 20)), cv::NORM_INF) <= 1.0,
            "average should be numerically stable");
}

void testFailuresAndCancellation(const std::filesystem::path& root) {
    using namespace camerae_processing;
    requireThrows(
        [&] { renderAstroStack({}, root / "empty.png", neutralSettings()); },
        "empty input should throw"
    );

    const auto frame = root / "cancel.png";
    cv::imwrite(frame.string(), cv::Mat(8, 8, CV_8UC3, cv::Scalar(20, 20, 20)));
    requireThrows(
        [&] { renderAstroStack({frame}, root / "cancel-output.png", neutralSettings(), cancelImmediately); },
        "cancelled processing should throw"
    );
}

} // namespace

int main() {
    const auto root = std::filesystem::temp_directory_path() /
        ("camerae-processing-tests-" + std::to_string(std::chrono::steady_clock::now().time_since_epoch().count()));
    std::filesystem::create_directories(root);
    try {
        testProfiles();
        testSyntheticAverage(root);
        testFailuresAndCancellation(root);
        std::filesystem::remove_all(root);
        std::cout << "camerae_processing_tests passed\n";
        return 0;
    } catch (const std::exception& error) {
        std::filesystem::remove_all(root);
        std::cerr << "camerae_processing_tests failed: " << error.what() << "\n";
        return 1;
    }
}
