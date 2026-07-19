#pragma once

#include "camerae_vision/alignment_quality.hpp"

#include <cstddef>
#include <optional>

namespace camerae_vision {

struct CaptureAlignmentSessionDiagnostics {
    std::size_t completedEvaluations = 0;
    std::size_t cancelledEvaluations = 0;
    std::size_t referenceUpdates = 0;
    std::size_t referenceFeatureExtractions = 0;
    std::size_t retainedReferenceBytes = 0;
    std::size_t estimatedRetainedBytes = 0;
};

class CaptureAlignmentSession {
public:
    explicit CaptureAlignmentSession(
        const cv::Mat& reference,
        AlignmentQualityPreset preset = AlignmentQualityPreset::CaptureFast
    );

    std::optional<CaptureAlignmentQuality> evaluate(const cv::Mat& moving);
    void updateReference(const cv::Mat& reference);
    void cancel();
    void resume();
    bool isCancelled() const;
    CaptureAlignmentSessionDiagnostics diagnostics() const;

private:
    cv::Mat reference_;
    AlignmentQualityEvaluator evaluator_;
    bool cancelled_ = false;
    CaptureAlignmentSessionDiagnostics diagnostics_;
};

} // namespace camerae_vision
