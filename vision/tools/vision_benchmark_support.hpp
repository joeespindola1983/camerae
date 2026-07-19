#pragma once

#include <cstddef>
#include <string>

namespace camerae_vision::benchmark {

struct BenchmarkLatency {
    std::size_t samples = 0;
    double p50Milliseconds = 0.0;
    double p95Milliseconds = 0.0;
    double maximumMilliseconds = 0.0;
};

struct VisionBenchmarkReport {
    std::size_t iterations = 0;
    BenchmarkLatency captureFast;
    BenchmarkLatency finalAutomatic;
    std::size_t peakEstimatedRetainedBytes = 0;
};

VisionBenchmarkReport runSyntheticBenchmark(std::size_t iterations);
std::string benchmarkJSON(const VisionBenchmarkReport& report);

} // namespace camerae_vision::benchmark
