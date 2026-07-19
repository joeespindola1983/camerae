#pragma once

#include "camerae_vision/alignment_quality.hpp"

#include <cstddef>
#include <memory>
#include <optional>

namespace camerae_vision {

enum class CaptureSupportComponentID {
    AlignmentQuality
};

enum class CaptureSupportCadence {
    Conservative,
    Balanced,
    Responsive
};

struct CaptureSupportSettings {
    CaptureSupportComponentID id = CaptureSupportComponentID::AlignmentQuality;
    bool enabled = false;
    CaptureSupportCadence cadence = CaptureSupportCadence::Balanced;
};

struct CaptureSupportDiagnostics {
    std::size_t evaluatorInstancesCreated = 0;
    std::size_t scheduledEvaluations = 0;
};

double captureSupportAnalysisFPS(CaptureSupportCadence cadence);

class AlignmentQualityCaptureSupport {
public:
    explicit AlignmentQualityCaptureSupport(CaptureSupportSettings settings);

    std::optional<CaptureAlignmentQuality> evaluateIfEnabled(
        const cv::Mat& reference,
        const cv::Mat& moving
    );

    const CaptureSupportSettings& settings() const;
    const CaptureSupportDiagnostics& diagnostics() const;

private:
    CaptureSupportSettings settings_;
    CaptureSupportDiagnostics diagnostics_;
    std::unique_ptr<AlignmentQualityEvaluator> evaluator_;
};

} // namespace camerae_vision
