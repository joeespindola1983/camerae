#include "camerae_vision/capture_alignment_session.hpp"

#include <stdexcept>

namespace camerae_vision {
namespace {

std::size_t matrixBytes(const cv::Mat& image) {
    return image.total() * image.elemSize();
}

void requireReference(const cv::Mat& reference) {
    if (reference.empty()) {
        throw std::invalid_argument("referencia da sessao nao pode ser vazia");
    }
}

} // namespace

CaptureAlignmentSession::CaptureAlignmentSession(
    const cv::Mat& reference,
    AlignmentQualityPreset preset
) : evaluator_(preset) {
    requireReference(reference);
    reference_ = reference.clone();
    diagnostics_.retainedReferenceBytes = matrixBytes(reference_);
}

std::optional<CaptureAlignmentQuality> CaptureAlignmentSession::evaluate(const cv::Mat& moving) {
    if (cancelled_) {
        ++diagnostics_.cancelledEvaluations;
        return std::nullopt;
    }
    CaptureAlignmentQuality quality = evaluator_.evaluate(reference_, moving);
    ++diagnostics_.completedEvaluations;
    return quality;
}

void CaptureAlignmentSession::updateReference(const cv::Mat& reference) {
    requireReference(reference);
    reference_ = reference.clone();
    evaluator_.resetReference();
    ++diagnostics_.referenceUpdates;
    diagnostics_.retainedReferenceBytes = matrixBytes(reference_);
}

void CaptureAlignmentSession::cancel() {
    cancelled_ = true;
}

void CaptureAlignmentSession::resume() {
    cancelled_ = false;
}

bool CaptureAlignmentSession::isCancelled() const {
    return cancelled_;
}

CaptureAlignmentSessionDiagnostics CaptureAlignmentSession::diagnostics() const {
    CaptureAlignmentSessionDiagnostics current = diagnostics_;
    const auto& evaluatorDiagnostics = evaluator_.diagnostics();
    current.referenceFeatureExtractions = evaluatorDiagnostics.referenceFeatureExtractions;
    current.estimatedRetainedBytes = current.retainedReferenceBytes +
        evaluatorDiagnostics.estimatedReferenceCacheBytes;
    return current;
}

} // namespace camerae_vision
