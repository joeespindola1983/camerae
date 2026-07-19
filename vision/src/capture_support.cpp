#include "camerae_vision/capture_support.hpp"

#include <stdexcept>
#include <utility>

namespace camerae_vision {

double captureSupportAnalysisFPS(CaptureSupportCadence cadence) {
    switch (cadence) {
    case CaptureSupportCadence::Conservative:
        return 1.0;
    case CaptureSupportCadence::Balanced:
        return 2.0;
    case CaptureSupportCadence::Responsive:
        return 4.0;
    }
    throw std::invalid_argument("cadencia de suporte desconhecida");
}

AlignmentQualityCaptureSupport::AlignmentQualityCaptureSupport(
    CaptureSupportSettings settings
) : settings_(std::move(settings)) {
    if (settings_.id != CaptureSupportComponentID::AlignmentQuality) {
        throw std::invalid_argument("componente de suporte desconhecido");
    }
}

std::optional<CaptureAlignmentQuality> AlignmentQualityCaptureSupport::evaluateIfEnabled(
    const cv::Mat& reference,
    const cv::Mat& moving
) {
    if (!settings_.enabled) {
        return std::nullopt;
    }
    if (!evaluator_) {
        evaluator_ = std::make_unique<AlignmentQualityEvaluator>(
            AlignmentQualityPreset::CaptureFast
        );
        ++diagnostics_.evaluatorInstancesCreated;
    }
    ++diagnostics_.scheduledEvaluations;
    return evaluator_->evaluate(reference, moving);
}

const CaptureSupportSettings& AlignmentQualityCaptureSupport::settings() const {
    return settings_;
}

const CaptureSupportDiagnostics& AlignmentQualityCaptureSupport::diagnostics() const {
    return diagnostics_;
}

} // namespace camerae_vision
