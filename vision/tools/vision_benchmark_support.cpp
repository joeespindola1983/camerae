#include "vision_benchmark_support.hpp"

#include "camerae_vision/automatic_alignment.hpp"
#include "camerae_vision/capture_alignment_session.hpp"
#include "camerae_vision/diagnostics.hpp"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <iomanip>
#include <sstream>
#include <stdexcept>
#include <vector>

#include <opencv2/core.hpp>
#include <opencv2/imgproc.hpp>

namespace camerae_vision::benchmark {
namespace {

cv::Mat makeFixture() {
    cv::Mat image(360, 480, CV_8UC3);
    cv::RNG random(20260720);
    random.fill(image, cv::RNG::UNIFORM, 0, 255);
    cv::GaussianBlur(image, image, cv::Size(5, 5), 1.0);
    for (int row = 45; row < image.rows; row += 70) {
        for (int column = 45; column < image.cols; column += 85) {
            cv::circle(image, cv::Point(column, row), 14,
                       cv::Scalar(column % 255, row % 255, (row + column) % 255), 3);
        }
    }
    cv::putText(image, "BENCH", cv::Point(125, 325), cv::FONT_HERSHEY_SIMPLEX,
                1.1, cv::Scalar::all(250), 3, cv::LINE_AA);
    return image;
}

cv::Mat movingFrame(const cv::Mat& reference, std::size_t iteration) {
    const double x = 4.0 + static_cast<double>(iteration % 7);
    const double y = -2.0 - static_cast<double>(iteration % 5);
    const cv::Mat transform = (cv::Mat_<double>(2, 3) << 1.0, 0.0, -x, 0.0, 1.0, -y);
    cv::Mat moving;
    cv::warpAffine(reference, moving, transform, reference.size(), cv::INTER_LINEAR,
                   cv::BORDER_CONSTANT, cv::Scalar::all(0));
    return moving;
}

double measuredMilliseconds(const std::chrono::steady_clock::time_point& started) {
    return std::chrono::duration<double, std::milli>(
        std::chrono::steady_clock::now() - started
    ).count();
}

double nearestRank(const std::vector<double>& sorted, double percentile) {
    if (sorted.empty()) return 0.0;
    const auto rank = std::max<std::size_t>(
        1, static_cast<std::size_t>(std::ceil(percentile * sorted.size()))
    );
    return sorted[std::min(rank - 1, sorted.size() - 1)];
}

BenchmarkLatency summarize(std::vector<double> samples) {
    std::sort(samples.begin(), samples.end());
    return {
        .samples = samples.size(),
        .p50Milliseconds = nearestRank(samples, 0.50),
        .p95Milliseconds = nearestRank(samples, 0.95),
        .maximumMilliseconds = samples.empty() ? 0.0 : samples.back()
    };
}

} // namespace

VisionBenchmarkReport runSyntheticBenchmark(std::size_t iterations) {
    if (iterations == 0) {
        throw std::invalid_argument("benchmark requer ao menos uma iteracao");
    }
    const cv::Mat reference = makeFixture();
    CaptureAlignmentSession session(reference);
    AutomaticAlignmentSettings finalSettings;
    finalSettings.alignment.maxDimension = 0;
    finalSettings.alignment.maxFeatures = 2500;
    finalSettings.alignment.matchRatio = 0.85f;
    finalSettings.alignment.ransacThreshold = 2.0;
    std::vector<double> captureLatencies;
    std::vector<double> finalLatencies;
    captureLatencies.reserve(iterations);
    finalLatencies.reserve(iterations);

    for (std::size_t iteration = 0; iteration < iterations; ++iteration) {
        const cv::Mat moving = movingFrame(reference, iteration);
        auto started = std::chrono::steady_clock::now();
        const auto capture = session.evaluate(moving);
        captureLatencies.push_back(measuredMilliseconds(started));
        if (!capture.has_value()) {
            throw std::runtime_error("sessao de benchmark cancelou inesperadamente");
        }

        started = std::chrono::steady_clock::now();
        alignImagesAutomatically(reference, moving, finalSettings);
        finalLatencies.push_back(measuredMilliseconds(started));
    }

    return {
        .iterations = iterations,
        .captureFast = summarize(std::move(captureLatencies)),
        .finalAutomatic = summarize(std::move(finalLatencies)),
        .peakEstimatedRetainedBytes = session.diagnostics().estimatedRetainedBytes
    };
}

std::string benchmarkJSON(const VisionBenchmarkReport& report) {
    const auto writeLatency = [](std::ostringstream& output, const BenchmarkLatency& latency) {
        output << "{\"samples\": " << latency.samples
            << ", \"p50Milliseconds\": " << latency.p50Milliseconds
            << ", \"p95Milliseconds\": " << latency.p95Milliseconds
            << ", \"maximumMilliseconds\": " << latency.maximumMilliseconds << "}";
    };
    std::ostringstream output;
    output << std::fixed << std::setprecision(6)
        << "{\n"
        << "  \"schemaVersion\": " << cameraeVisionDiagnosticsSchemaVersion << ",\n"
        << "  \"iterations\": " << report.iterations << ",\n"
        << "  \"peakEstimatedRetainedBytes\": " << report.peakEstimatedRetainedBytes << ",\n"
        << "  \"captureFast\": ";
    writeLatency(output, report.captureFast);
    output << ",\n  \"finalAutomatic\": ";
    writeLatency(output, report.finalAutomatic);
    output << "\n}\n";
    return output.str();
}

} // namespace camerae_vision::benchmark
