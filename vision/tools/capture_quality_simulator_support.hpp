#pragma once

#include "camerae_vision/alignment_quality.hpp"

#include <cstddef>
#include <string>
#include <vector>

namespace camerae_vision::simulator {

struct CaptureSimulationSettings {
    double captureFPS = 30.0;
    double analysisFPS = 2.0;
    bool latestOnly = true;
};

struct CaptureSchedule {
    std::vector<std::size_t> frameIndices;
    std::size_t receivedFrames = 0;
    std::size_t droppedFrames = 0;
    std::size_t maximumPendingFrames = 0;
};

struct LatencySummary {
    double p50Milliseconds = 0.0;
    double p95Milliseconds = 0.0;
    double maximumMilliseconds = 0.0;
};

class LatestOnlyWorkerClock {
public:
    bool canStart(double frameTimestampSeconds) const;
    void didStart(double frameTimestampSeconds, double latencyMilliseconds);

private:
    double availableAtSeconds_ = 0.0;
};

struct CaptureSimulationFrameResult {
    std::size_t sourceIndex = 0;
    std::string sourcePath;
    AlignmentDecision decision = AlignmentDecision::Reject;
    double score = 0.0;
    double overlapRatio = 0.0;
    double reprojectionRMSE = 0.0;
    double edgeAlignmentError = 0.0;
    double latencyMilliseconds = 0.0;
    AlignmentMotionModel selectedModel = AlignmentMotionModel::Similarity;
    std::vector<std::string> reasons;
};

struct CaptureSimulationReport {
    std::vector<CaptureSimulationFrameResult> frames;
    std::size_t receivedFrames = 0;
    std::size_t analyzedFrames = 0;
    std::size_t droppedFrames = 0;
    std::size_t maximumPendingFrames = 0;
    std::size_t peakRetainedBytes = 0;
    std::size_t acceptedFrames = 0;
    std::size_t reviewFrames = 0;
    std::size_t rejectedFrames = 0;
    LatencySummary latency;
};

CaptureSchedule buildSchedule(
    std::size_t frameCount,
    const CaptureSimulationSettings& settings
);

LatencySummary summarizeLatencies(std::vector<double> milliseconds);
void finalizeReport(CaptureSimulationReport& report);
std::string reportJSON(const CaptureSimulationReport& report);

} // namespace camerae_vision::simulator
