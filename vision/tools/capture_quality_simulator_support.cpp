#include "capture_quality_simulator_support.hpp"

#include <algorithm>
#include <cmath>
#include <iomanip>
#include <sstream>
#include <stdexcept>
#include <utility>

namespace camerae_vision::simulator {
namespace {

std::string escapedJSON(const std::string& value) {
    std::string output;
    output.reserve(value.size());
    for (const char character : value) {
        switch (character) {
        case '\\': output += "\\\\"; break;
        case '"': output += "\\\""; break;
        case '\n': output += "\\n"; break;
        case '\r': output += "\\r"; break;
        case '\t': output += "\\t"; break;
        default: output += character; break;
        }
    }
    return output;
}

double percentage(std::size_t count, std::size_t total) {
    return total == 0 ? 0.0 : 100.0 * static_cast<double>(count) / static_cast<double>(total);
}

double nearestRank(const std::vector<double>& sorted, double percentile) {
    if (sorted.empty()) {
        return 0.0;
    }
    const std::size_t rank = std::max<std::size_t>(
        1, static_cast<std::size_t>(std::ceil(percentile * sorted.size()))
    );
    return sorted[std::min(rank - 1, sorted.size() - 1)];
}

} // namespace

CaptureSchedule buildSchedule(
    std::size_t frameCount,
    const CaptureSimulationSettings& settings
) {
    if (settings.captureFPS <= 0.0 || settings.analysisFPS <= 0.0) {
        throw std::invalid_argument("captureFPS e analysisFPS devem ser positivos");
    }
    CaptureSchedule schedule;
    schedule.receivedFrames = frameCount;
    if (frameCount == 0) {
        return schedule;
    }
    if (!settings.latestOnly) {
        schedule.frameIndices.resize(frameCount);
        for (std::size_t index = 0; index < frameCount; ++index) {
            schedule.frameIndices[index] = index;
        }
        schedule.maximumPendingFrames = frameCount;
        return schedule;
    }

    const double lastTimestamp = static_cast<double>(frameCount - 1) / settings.captureFPS;
    const double analysisInterval = 1.0 / settings.analysisFPS;
    for (double analysisTimestamp = 0.0;
         analysisTimestamp <= lastTimestamp + 1e-9;
         analysisTimestamp += analysisInterval) {
        const auto index = static_cast<std::size_t>(
            std::floor(analysisTimestamp * settings.captureFPS + 1e-9)
        );
        const std::size_t bounded = std::min(index, frameCount - 1);
        if (schedule.frameIndices.empty() || schedule.frameIndices.back() != bounded) {
            schedule.frameIndices.push_back(bounded);
        }
    }
    schedule.droppedFrames = frameCount - schedule.frameIndices.size();
    schedule.maximumPendingFrames = 1;
    return schedule;
}

bool LatestOnlyWorkerClock::canStart(double frameTimestampSeconds) const {
    return frameTimestampSeconds + 1e-9 >= availableAtSeconds_;
}

void LatestOnlyWorkerClock::didStart(
    double frameTimestampSeconds,
    double latencyMilliseconds
) {
    if (frameTimestampSeconds < 0.0 || latencyMilliseconds < 0.0) {
        throw std::invalid_argument("timestamp e latencia nao podem ser negativos");
    }
    availableAtSeconds_ = frameTimestampSeconds + latencyMilliseconds / 1000.0;
}

LatencySummary summarizeLatencies(std::vector<double> milliseconds) {
    std::sort(milliseconds.begin(), milliseconds.end());
    return {
        .p50Milliseconds = nearestRank(milliseconds, 0.50),
        .p95Milliseconds = nearestRank(milliseconds, 0.95),
        .maximumMilliseconds = milliseconds.empty() ? 0.0 : milliseconds.back()
    };
}

void finalizeReport(CaptureSimulationReport& report) {
    report.analyzedFrames = report.frames.size();
    report.acceptedFrames = 0;
    report.reviewFrames = 0;
    report.rejectedFrames = 0;
    std::vector<double> latencies;
    latencies.reserve(report.frames.size());
    for (const auto& frame : report.frames) {
        latencies.push_back(frame.latencyMilliseconds);
        switch (frame.decision) {
        case AlignmentDecision::Accept: ++report.acceptedFrames; break;
        case AlignmentDecision::Review: ++report.reviewFrames; break;
        case AlignmentDecision::Reject: ++report.rejectedFrames; break;
        }
    }
    report.latency = summarizeLatencies(std::move(latencies));
}

std::string reportJSON(const CaptureSimulationReport& report) {
    std::ostringstream output;
    output << std::fixed << std::setprecision(6)
        << "{\n"
        << "  \"schemaVersion\": " << cameraeVisionDiagnosticsSchemaVersion << ",\n"
        << "  \"receivedFrames\": " << report.receivedFrames << ",\n"
        << "  \"analyzedFrames\": " << report.analyzedFrames << ",\n"
        << "  \"droppedFrames\": " << report.droppedFrames << ",\n"
        << "  \"maximumPendingFrames\": " << report.maximumPendingFrames << ",\n"
        << "  \"peakRetainedBytes\": " << report.peakRetainedBytes << ",\n"
        << "  \"latency\": {\n"
        << "    \"p50Milliseconds\": " << report.latency.p50Milliseconds << ",\n"
        << "    \"p95Milliseconds\": " << report.latency.p95Milliseconds << ",\n"
        << "    \"maximumMilliseconds\": " << report.latency.maximumMilliseconds << "\n"
        << "  },\n"
        << "  \"decisionPercentages\": {\n"
        << "    \"accept\": " << percentage(report.acceptedFrames, report.analyzedFrames) << ",\n"
        << "    \"review\": " << percentage(report.reviewFrames, report.analyzedFrames) << ",\n"
        << "    \"reject\": " << percentage(report.rejectedFrames, report.analyzedFrames) << "\n"
        << "  },\n"
        << "  \"decisionCounts\": {\n"
        << "    \"accept\": " << report.acceptedFrames << ",\n"
        << "    \"review\": " << report.reviewFrames << ",\n"
        << "    \"reject\": " << report.rejectedFrames << "\n"
        << "  },\n"
        << "  \"frames\": [";
    for (std::size_t index = 0; index < report.frames.size(); ++index) {
        const auto& frame = report.frames[index];
        output << (index == 0 ? "\n" : ",\n")
            << "    {\n"
            << "      \"sourceIndex\": " << frame.sourceIndex << ",\n"
            << "      \"sourcePath\": \"" << escapedJSON(frame.sourcePath) << "\",\n"
            << "      \"decision\": \"" << alignmentDecisionName(frame.decision) << "\",\n"
            << "      \"score\": " << frame.score << ",\n"
            << "      \"selectedModel\": \"" << alignmentMotionModelName(frame.selectedModel) << "\",\n"
            << "      \"overlapRatio\": " << frame.overlapRatio << ",\n"
            << "      \"reprojectionRMSE\": " << frame.reprojectionRMSE << ",\n"
            << "      \"edgeAlignmentError\": " << frame.edgeAlignmentError << ",\n"
            << "      \"latencyMilliseconds\": " << frame.latencyMilliseconds << ",\n"
            << "      \"reasonCodes\": [";
        for (std::size_t reasonIndex = 0; reasonIndex < frame.reasonCodes.size(); ++reasonIndex) {
            output << (reasonIndex == 0 ? "" : ", ")
                << "\"" << alignmentReasonCodeName(frame.reasonCodes[reasonIndex]) << "\"";
        }
        output << "],\n"
            << "      \"reasons\": [";
        for (std::size_t reasonIndex = 0; reasonIndex < frame.reasons.size(); ++reasonIndex) {
            output << (reasonIndex == 0 ? "" : ", ")
                << "\"" << escapedJSON(frame.reasons[reasonIndex]) << "\"";
        }
        output << "]\n    }";
    }
    if (!report.frames.empty()) {
        output << "\n  ";
    }
    output << "]\n}\n";
    return output.str();
}

} // namespace camerae_vision::simulator
