#import "CameraeVisionCaptureSession.h"

#include "camerae_vision/capture_alignment_session.hpp"
#include "camerae_vision/diagnostics.hpp"

#include <opencv2/core.hpp>
#include <opencv2/imgproc.hpp>

#include <memory>
#include <mutex>
#include <stdexcept>

NSErrorDomain const CameraeVisionErrorDomain = @"Camerae.Vision";

namespace {

constexpr int captureFastMaxDimension = 640;

NSError *MakeError(CameraeVisionErrorCode code, NSString *message) {
    return [NSError errorWithDomain:CameraeVisionErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

bool Fail(NSError **error, CameraeVisionErrorCode code, NSString *message) {
    if (error != nullptr) {
        *error = MakeError(code, message);
    }
    return false;
}

class PixelBufferReadLock final {
public:
    explicit PixelBufferReadLock(CVPixelBufferRef pixelBuffer)
        : pixelBuffer_(pixelBuffer),
          status_(CVPixelBufferLockBaseAddress(pixelBuffer_, kCVPixelBufferLock_ReadOnly)) {}

    ~PixelBufferReadLock() {
        if (status_ == kCVReturnSuccess) {
            CVPixelBufferUnlockBaseAddress(pixelBuffer_, kCVPixelBufferLock_ReadOnly);
        }
    }

    PixelBufferReadLock(const PixelBufferReadLock &) = delete;
    PixelBufferReadLock &operator=(const PixelBufferReadLock &) = delete;

    bool succeeded() const { return status_ == kCVReturnSuccess; }

private:
    CVPixelBufferRef pixelBuffer_;
    CVReturn status_;
};

bool PixelBufferToMat(
    CVPixelBufferRef pixelBuffer,
    CEVImageOrientation orientation,
    cv::Mat &output,
    NSError **error
) {
    if (pixelBuffer == nullptr) {
        return Fail(error, CameraeVisionErrorInvalidInput, @"Pixel buffer ausente.");
    }
    if (CVPixelBufferGetPixelFormatType(pixelBuffer) != kCVPixelFormatType_32BGRA) {
        return Fail(error, CameraeVisionErrorUnsupportedPixelFormat,
                    @"Camerae Vision requer pixel buffer BGRA.");
    }

    PixelBufferReadLock readLock(pixelBuffer);
    if (!readLock.succeeded()) {
        return Fail(error, CameraeVisionErrorPixelBufferLockFailed,
                    @"Nao foi possivel bloquear o pixel buffer para leitura.");
    }

    try {
        void *baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer);
        const size_t width = CVPixelBufferGetWidth(pixelBuffer);
        const size_t height = CVPixelBufferGetHeight(pixelBuffer);
        const size_t bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer);
        if (baseAddress == nullptr || width == 0 || height == 0 || bytesPerRow < width * 4) {
            return Fail(error, CameraeVisionErrorInvalidInput, @"Pixel buffer BGRA invalido.");
        }

        cv::Mat view(static_cast<int>(height), static_cast<int>(width), CV_8UC4,
                     baseAddress, bytesPerRow);
        const int longestSide = static_cast<int>(std::max(width, height));
        cv::Mat reduced;
        if (longestSide > captureFastMaxDimension) {
            const double scale = static_cast<double>(captureFastMaxDimension) /
                static_cast<double>(longestSide);
            cv::resize(view, reduced, cv::Size(), scale, scale, cv::INTER_AREA);
        } else {
            view.copyTo(reduced);
        }

        switch (orientation) {
        case CEVImageOrientationUp:
            output = std::move(reduced);
            break;
        case CEVImageOrientationRight:
            cv::rotate(reduced, output, cv::ROTATE_90_CLOCKWISE);
            break;
        case CEVImageOrientationDown:
            cv::rotate(reduced, output, cv::ROTATE_180);
            break;
        case CEVImageOrientationLeft:
            cv::rotate(reduced, output, cv::ROTATE_90_COUNTERCLOCKWISE);
            break;
        default:
            return Fail(error, CameraeVisionErrorInvalidInput, @"Orientacao de imagem invalida.");
        }
        return !output.empty();
    } catch (const std::exception &exception) {
        return Fail(error, CameraeVisionErrorEvaluationFailed,
                    [NSString stringWithUTF8String:exception.what()]);
    }
}

CEVAlignmentDecision MapDecision(camerae_vision::AlignmentDecision decision) {
    switch (decision) {
    case camerae_vision::AlignmentDecision::Accept: return CEVAlignmentDecisionAccept;
    case camerae_vision::AlignmentDecision::Review: return CEVAlignmentDecisionReview;
    case camerae_vision::AlignmentDecision::Reject: return CEVAlignmentDecisionReject;
    }
}

NSArray<NSNumber *> *TransformValues(const cv::Mat &transform) {
    if (transform.rows != 3 || transform.cols != 3) { return @[]; }
    cv::Mat converted;
    transform.convertTo(converted, CV_64F);
    NSMutableArray<NSNumber *> *values = [NSMutableArray arrayWithCapacity:9];
    for (int row = 0; row < 3; ++row) {
        for (int column = 0; column < 3; ++column) {
            [values addObject:@(converted.at<double>(row, column))];
        }
    }
    return values;
}

NSArray<NSString *> *ReasonCodeValues(
    const std::vector<camerae_vision::AlignmentReasonCode> &codes
) {
    NSMutableArray<NSString *> *values = [NSMutableArray arrayWithCapacity:codes.size()];
    for (const auto code : codes) {
        [values addObject:[NSString stringWithUTF8String:
            camerae_vision::alignmentReasonCodeName(code).c_str()]];
    }
    return values;
}

} // namespace

@interface CEVCaptureAlignmentResult ()
@property(nonatomic, readwrite) NSInteger schemaVersion;
@property(nonatomic, readwrite) CEVAlignmentDecision decision;
@property(nonatomic, readwrite) double score;
@property(nonatomic, readwrite) double overlapRatio;
@property(nonatomic, readwrite) double reprojectionRMSE;
@property(nonatomic, readwrite) double edgeAlignmentError;
@property(nonatomic, readwrite) double latencyMilliseconds;
@property(nonatomic, copy, readwrite) NSString *selectedModel;
@property(nonatomic, copy, readwrite) NSArray<NSString *> *reasonCodes;
@property(nonatomic, copy, readwrite) NSArray<NSNumber *> *transform3x3;
@end

@implementation CEVCaptureAlignmentResult
@end

@interface CEVCaptureAlignmentDiagnostics ()
@property(nonatomic, readwrite) NSUInteger completedEvaluations;
@property(nonatomic, readwrite) NSUInteger cancelledEvaluations;
@property(nonatomic, readwrite) NSUInteger referenceUpdates;
@property(nonatomic, readwrite) NSUInteger referenceFeatureExtractions;
@property(nonatomic, readwrite) NSUInteger retainedReferenceBytes;
@property(nonatomic, readwrite) NSUInteger estimatedRetainedBytes;
@end

@implementation CEVCaptureAlignmentDiagnostics
@end

@implementation CameraeVisionCaptureSession {
    std::unique_ptr<camerae_vision::CaptureAlignmentSession> _session;
    std::mutex _mutex;
}

- (nullable instancetype)initWithReferencePixelBuffer:(CVPixelBufferRef)referencePixelBuffer
                                           orientation:(CEVImageOrientation)orientation
                                                 error:(NSError **)error {
    self = [super init];
    if (self == nil) { return nil; }
    if (error != nullptr) { *error = nil; }

    cv::Mat reference;
    if (!PixelBufferToMat(referencePixelBuffer, orientation, reference, error)) { return nil; }
    try {
        _session = std::make_unique<camerae_vision::CaptureAlignmentSession>(reference);
    } catch (const std::exception &exception) {
        if (error != nullptr) {
            *error = MakeError(CameraeVisionErrorEvaluationFailed,
                               [NSString stringWithUTF8String:exception.what()]);
        }
        return nil;
    }
    return self;
}

- (nullable CEVCaptureAlignmentResult *)evaluatePixelBuffer:(CVPixelBufferRef)pixelBuffer
                                                 orientation:(CEVImageOrientation)orientation
                                                       error:(NSError **)error {
    std::lock_guard<std::mutex> lock(_mutex);
    if (error != nullptr) { *error = nil; }
    if (_session == nullptr || _session->isCancelled()) {
        if (error != nullptr) {
            *error = MakeError(CameraeVisionErrorCancelled, @"A avaliacao foi cancelada.");
        }
        return nil;
    }

    cv::Mat moving;
    if (!PixelBufferToMat(pixelBuffer, orientation, moving, error)) { return nil; }
    try {
        const auto quality = _session->evaluate(moving);
        if (!quality.has_value()) { return nil; }

        CEVCaptureAlignmentResult *result = [[CEVCaptureAlignmentResult alloc] init];
        result.schemaVersion = camerae_vision::cameraeVisionDiagnosticsSchemaVersion;
        result.decision = MapDecision(quality->decision);
        result.score = quality->score;
        result.overlapRatio = quality->overlapRatio;
        result.reprojectionRMSE = quality->reprojectionRMSE;
        result.edgeAlignmentError = quality->edgeAlignmentError;
        result.latencyMilliseconds = quality->estimatedLatencyMilliseconds;
        result.selectedModel = [NSString stringWithUTF8String:
            camerae_vision::alignmentMotionModelName(quality->selectedModel).c_str()];
        result.reasonCodes = ReasonCodeValues(quality->reasonCodes);
        result.transform3x3 = TransformValues(quality->transform);
        return result;
    } catch (const std::exception &exception) {
        if (error != nullptr) {
            *error = MakeError(CameraeVisionErrorEvaluationFailed,
                               [NSString stringWithUTF8String:exception.what()]);
        }
        return nil;
    }
}

- (BOOL)updateReferencePixelBuffer:(CVPixelBufferRef)referencePixelBuffer
                       orientation:(CEVImageOrientation)orientation
                             error:(NSError **)error {
    std::lock_guard<std::mutex> lock(_mutex);
    if (error != nullptr) { *error = nil; }
    cv::Mat reference;
    if (!PixelBufferToMat(referencePixelBuffer, orientation, reference, error)) { return NO; }
    try {
        _session->updateReference(reference);
        return YES;
    } catch (const std::exception &exception) {
        return Fail(error, CameraeVisionErrorEvaluationFailed,
                    [NSString stringWithUTF8String:exception.what()]);
    }
}

- (void)cancel {
    std::lock_guard<std::mutex> lock(_mutex);
    if (_session != nullptr) { _session->cancel(); }
}

- (void)resume {
    std::lock_guard<std::mutex> lock(_mutex);
    if (_session != nullptr) { _session->resume(); }
}

- (CEVCaptureAlignmentDiagnostics *)diagnostics {
    std::lock_guard<std::mutex> lock(_mutex);
    CEVCaptureAlignmentDiagnostics *result = [[CEVCaptureAlignmentDiagnostics alloc] init];
    if (_session == nullptr) { return result; }
    const auto diagnostics = _session->diagnostics();
    result.completedEvaluations = diagnostics.completedEvaluations;
    result.cancelledEvaluations = diagnostics.cancelledEvaluations;
    result.referenceUpdates = diagnostics.referenceUpdates;
    result.referenceFeatureExtractions = diagnostics.referenceFeatureExtractions;
    result.retainedReferenceBytes = diagnostics.retainedReferenceBytes;
    result.estimatedRetainedBytes = diagnostics.estimatedRetainedBytes;
    return result;
}

@end
