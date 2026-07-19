#include "capture_quality_simulator_support.hpp"

#include <cmath>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

namespace {

using namespace camerae_vision::simulator;

void require(bool condition, const std::string& message) {
    if (!condition) {
        throw std::runtime_error(message);
    }
}

void requireNear(double actual, double expected, const std::string& message) {
    if (std::abs(actual - expected) > 1e-9) {
        throw std::runtime_error(message + ": actual=" + std::to_string(actual));
    }
}

void testLatestOnlyScheduleDropsSupersededFrames() {
    CaptureSimulationSettings settings;
    settings.captureFPS = 30.0;
    settings.analysisFPS = 2.0;
    settings.latestOnly = true;

    const auto schedule = buildSchedule(61, settings);

    require(schedule.frameIndices == std::vector<std::size_t>({0, 15, 30, 45, 60}),
            "2 Hz analysis should retain the latest frame at each 500 ms cadence");
    require(schedule.receivedFrames == 61, "all frames should be counted as received");
    require(schedule.droppedFrames == 56, "superseded frames should be counted as dropped");
    require(schedule.maximumPendingFrames == 1, "latest-only queue must remain bounded to one frame");
}

void testLongSequenceDoesNotAccumulateBacklog() {
    CaptureSimulationSettings settings;
    settings.captureFPS = 30.0;
    settings.analysisFPS = 2.0;
    settings.latestOnly = true;

    const auto schedule = buildSchedule(3600, settings);

    require(schedule.maximumPendingFrames == 1, "long sequences must keep bounded backpressure");
    require(schedule.frameIndices.size() <= 241, "two minutes should analyze at most about 240 frames");
    require(schedule.receivedFrames == schedule.frameIndices.size() + schedule.droppedFrames,
            "received frames should equal analyzed candidates plus drops");
}

void testLatencyPercentilesUseNearestRank() {
    const auto latency = summarizeLatencies({1.0, 2.0, 3.0, 4.0, 100.0});

    requireNear(latency.p50Milliseconds, 3.0, "p50 should use nearest rank");
    requireNear(latency.p95Milliseconds, 100.0, "p95 should use nearest rank");
    requireNear(latency.maximumMilliseconds, 100.0, "maximum latency should be retained");
}

void testBusyWorkerDropsAnalysisSlotsWithoutBacklog() {
    LatestOnlyWorkerClock worker;

    require(worker.canStart(0.0), "worker should accept the first analysis slot");
    worker.didStart(0.0, 750.0);
    require(!worker.canStart(0.5), "750 ms work should drop the 500 ms analysis slot");
    require(worker.canStart(1.0), "worker should recover for the next available slot");
}

void testReportCountsDecisionsAndContainsRequiredJSONFields() {
    CaptureSimulationReport report;
    report.receivedFrames = 5;
    report.droppedFrames = 2;
    report.maximumPendingFrames = 1;
    report.peakRetainedBytes = 4096;
    report.frames = {
        {.decision = camerae_vision::AlignmentDecision::Accept, .latencyMilliseconds = 1.0},
        {.decision = camerae_vision::AlignmentDecision::Review, .latencyMilliseconds = 2.0},
        {.decision = camerae_vision::AlignmentDecision::Reject, .latencyMilliseconds = 3.0}
    };

    finalizeReport(report);
    const std::string json = reportJSON(report);

    require(report.acceptedFrames == 1 && report.reviewFrames == 1 && report.rejectedFrames == 1,
            "report should count every alignment decision");
    require(report.analyzedFrames == 3, "report should count analyzed frames");
    for (const std::string& field : {
             "\"p50Milliseconds\"", "\"p95Milliseconds\"", "\"maximumMilliseconds\"",
             "\"receivedFrames\"", "\"analyzedFrames\"", "\"droppedFrames\"",
             "\"peakRetainedBytes\"", "\"decisionPercentages\""}) {
        require(json.find(field) != std::string::npos, "JSON should contain " + field);
    }
}

} // namespace

int main() {
    try {
        testLatestOnlyScheduleDropsSupersededFrames();
        testLongSequenceDoesNotAccumulateBacklog();
        testLatencyPercentilesUseNearestRank();
        testBusyWorkerDropsAnalysisSlotsWithoutBacklog();
        testReportCountsDecisionsAndContainsRequiredJSONFields();
        std::cout << "camerae_capture_quality_simulator_tests passed\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "camerae_capture_quality_simulator_tests failed: " << error.what() << "\n";
        return 1;
    }
}
