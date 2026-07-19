#include "vision_benchmark_support.hpp"

#include <iostream>
#include <stdexcept>
#include <string>

namespace {

using namespace camerae_vision::benchmark;

void require(bool condition, const std::string& message) {
    if (!condition) {
        throw std::runtime_error(message);
    }
}

void testBenchmarkProducesBothPipelineMeasurements() {
    const VisionBenchmarkReport report = runSyntheticBenchmark(3);

    require(report.iterations == 3, "benchmark should retain requested iteration count");
    require(report.captureFast.samples == 3, "captureFast should measure every iteration");
    require(report.finalAutomatic.samples == 3, "final automatic should measure every iteration");
    require(report.captureFast.p95Milliseconds > 0.0, "captureFast p95 should be measured");
    require(report.finalAutomatic.p95Milliseconds > 0.0, "final automatic p95 should be measured");
    require(report.peakEstimatedRetainedBytes > 0, "benchmark should report retained memory");
}

void testBenchmarkGuardrailsCatchExplosiveRegressions() {
    const VisionBenchmarkReport report = runSyntheticBenchmark(3);

    require(report.captureFast.p95Milliseconds < 500.0,
            "captureFast p95 exceeded the desktop regression guardrail");
    require(report.finalAutomatic.p95Milliseconds < 5000.0,
            "final automatic p95 exceeded the desktop regression guardrail");
    require(report.peakEstimatedRetainedBytes < 16 * 1024 * 1024,
            "capture session memory exceeded the desktop regression guardrail");
}

void testBenchmarkJSONIsVersioned() {
    const std::string json = benchmarkJSON(runSyntheticBenchmark(1));

    require(json.find("\"schemaVersion\": 1") != std::string::npos,
            "benchmark JSON should declare schema v1");
    require(json.find("\"captureFast\"") != std::string::npos,
            "benchmark JSON should contain captureFast results");
    require(json.find("\"finalAutomatic\"") != std::string::npos,
            "benchmark JSON should contain final automatic results");
}

} // namespace

int main() {
    try {
        testBenchmarkProducesBothPipelineMeasurements();
        testBenchmarkGuardrailsCatchExplosiveRegressions();
        testBenchmarkJSONIsVersioned();
        std::cout << "camerae_vision_benchmark_tests passed\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "camerae_vision_benchmark_tests failed: " << error.what() << "\n";
        return 1;
    }
}
