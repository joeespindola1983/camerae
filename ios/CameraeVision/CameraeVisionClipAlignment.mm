#import "CameraeVisionClipAlignment.h"

#include "camerae_vision/alignment.hpp"
#include "camerae_vision/diagnostics.hpp"

#include <opencv2/core.hpp>
#include <opencv2/imgproc.hpp>

#include <algorithm>
#include <optional>
#include <stdexcept>

namespace {

NSError *MakeClipError(CameraeVisionErrorCode code, NSString *message) {
    return [NSError errorWithDomain:CameraeVisionErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

class PixelBufferReadLock final {
public:
    explicit PixelBufferReadLock(CVPixelBufferRef buffer)
        : buffer_(buffer),
          status_(CVPixelBufferLockBaseAddress(buffer, kCVPixelBufferLock_ReadOnly)) {}
    ~PixelBufferReadLock() {
        if (status_ == kCVReturnSuccess) {
            CVPixelBufferUnlockBaseAddress(buffer_, kCVPixelBufferLock_ReadOnly);
        }
    }
    bool succeeded() const { return status_ == kCVReturnSuccess; }
private:
    CVPixelBufferRef buffer_;
    CVReturn status_;
};

bool BufferToMat(
    CVPixelBufferRef buffer,
    CEVImageOrientation orientation,
    cv::Mat &output,
    NSError **error
) {
    if (buffer == nullptr) {
        if (error) { *error = MakeClipError(CameraeVisionErrorInvalidInput, @"Pixel buffer ausente."); }
        return false;
    }
    if (CVPixelBufferGetPixelFormatType(buffer) != kCVPixelFormatType_32BGRA) {
        if (error) {
            *error = MakeClipError(CameraeVisionErrorUnsupportedPixelFormat,
                                   @"Camerae Vision requer pixel buffer BGRA.");
        }
        return false;
    }

    PixelBufferReadLock lock(buffer);
    if (!lock.succeeded()) {
        if (error) {
            *error = MakeClipError(CameraeVisionErrorPixelBufferLockFailed,
                                   @"Nao foi possivel bloquear o pixel buffer.");
        }
        return false;
    }

    try {
        void *base = CVPixelBufferGetBaseAddress(buffer);
        const size_t width = CVPixelBufferGetWidth(buffer);
        const size_t height = CVPixelBufferGetHeight(buffer);
        const size_t stride = CVPixelBufferGetBytesPerRow(buffer);
        if (base == nullptr || width == 0 || height == 0 || stride < width * 4) {
            if (error) { *error = MakeClipError(CameraeVisionErrorInvalidInput, @"Pixel buffer invalido."); }
            return false;
        }
        cv::Mat view(static_cast<int>(height), static_cast<int>(width), CV_8UC4, base, stride);
        cv::Mat owned;
        view.copyTo(owned);
        switch (orientation) {
        case CEVImageOrientationUp: output = std::move(owned); break;
        case CEVImageOrientationRight: cv::rotate(owned, output, cv::ROTATE_90_CLOCKWISE); break;
        case CEVImageOrientationDown: cv::rotate(owned, output, cv::ROTATE_180); break;
        case CEVImageOrientationLeft: cv::rotate(owned, output, cv::ROTATE_90_COUNTERCLOCKWISE); break;
        default:
            if (error) { *error = MakeClipError(CameraeVisionErrorInvalidInput, @"Orientacao invalida."); }
            return false;
        }
        return !output.empty();
    } catch (const std::exception &exception) {
        if (error) {
            *error = MakeClipError(CameraeVisionErrorEvaluationFailed,
                                   [NSString stringWithUTF8String:exception.what()]);
        }
        return false;
    }
}

int DecisionRank(camerae_vision::AlignmentDecision decision) {
    switch (decision) {
    case camerae_vision::AlignmentDecision::Accept: return 2;
    case camerae_vision::AlignmentDecision::Review: return 1;
    case camerae_vision::AlignmentDecision::Reject: return 0;
    }
}

CEVAlignmentDecision MapDecision(camerae_vision::AlignmentDecision decision) {
    switch (decision) {
    case camerae_vision::AlignmentDecision::Accept: return CEVAlignmentDecisionAccept;
    case camerae_vision::AlignmentDecision::Review: return CEVAlignmentDecisionReview;
    case camerae_vision::AlignmentDecision::Reject: return CEVAlignmentDecisionReject;
    }
}

std::optional<camerae_vision::AlignmentResult> TryModel(
    const cv::Mat &reference,
    const cv::Mat &moving,
    camerae_vision::AlignmentMotionModel model
) {
    camerae_vision::AlignmentSettings settings;
    settings.motionModel = model;
    settings.maxDimension = 960;
    settings.maxFeatures = 3000;
    settings.matchRatio = 0.80f;
    settings.mutualMatching = true;
    settings.ransacThreshold = 2.5;
    try {
        return camerae_vision::alignImages(reference, moving, settings);
    } catch (const std::exception &) {
        return std::nullopt;
    }
}

NSArray<NSNumber *> *NormalizedTransform(const cv::Mat &transform, const cv::Size &size) {
    cv::Mat matrix;
    transform.convertTo(matrix, CV_64F);
    cv::Mat fromNormalized = (cv::Mat_<double>(3, 3) <<
        size.width, 0, 0,
        0, size.height, 0,
        0, 0, 1);
    cv::Mat toNormalized = (cv::Mat_<double>(3, 3) <<
        1.0 / size.width, 0, 0,
        0, 1.0 / size.height, 0,
        0, 0, 1);
    cv::Mat normalized = toNormalized * matrix * fromNormalized;
    NSMutableArray<NSNumber *> *values = [NSMutableArray arrayWithCapacity:9];
    for (int row = 0; row < 3; ++row) {
        for (int column = 0; column < 3; ++column) {
            [values addObject:@(normalized.at<double>(row, column))];
        }
    }
    return values;
}

NSArray<NSNumber *> *ValidRegion(const cv::Mat &mask) {
    if (mask.empty() || cv::countNonZero(mask) == 0) {
        return @[@0, @0, @0, @0];
    }

    std::vector<int> heights(mask.cols, 0);
    cv::Rect bounds;
    int largestArea = 0;
    for (int row = 0; row < mask.rows; ++row) {
        const auto *pixels = mask.ptr<unsigned char>(row);
        for (int column = 0; column < mask.cols; ++column) {
            heights[column] = pixels[column] == 0 ? 0 : heights[column] + 1;
        }

        std::vector<int> stack;
        stack.reserve(mask.cols + 1);
        for (int column = 0; column <= mask.cols; ++column) {
            const int height = column == mask.cols ? 0 : heights[column];
            while (!stack.empty() && heights[stack.back()] > height) {
                const int rectangleHeight = heights[stack.back()];
                stack.pop_back();
                const int left = stack.empty() ? 0 : stack.back() + 1;
                const int rectangleWidth = column - left;
                const int area = rectangleWidth * rectangleHeight;
                if (area > largestArea) {
                    largestArea = area;
                    bounds = cv::Rect(
                        left,
                        row - rectangleHeight + 1,
                        rectangleWidth,
                        rectangleHeight
                    );
                }
            }
            stack.push_back(column);
        }
    }
    if (largestArea == 0) { return @[@0, @0, @0, @0]; }
    return @[
        @(static_cast<double>(bounds.x) / mask.cols),
        @(static_cast<double>(bounds.y) / mask.rows),
        @(static_cast<double>(bounds.width) / mask.cols),
        @(static_cast<double>(bounds.height) / mask.rows)
    ];
}

NSArray<NSString *> *ReasonCodes(const camerae_vision::AlignmentResult &result) {
    NSMutableArray<NSString *> *values = [NSMutableArray array];
    for (const auto code : result.feasibility.reasonCodes) {
        [values addObject:[NSString stringWithUTF8String:
            camerae_vision::alignmentReasonCodeName(code).c_str()]];
    }
    return values;
}

} // namespace

@interface CEVClipAlignmentResult ()
@property(nonatomic, readwrite) NSInteger schemaVersion;
@property(nonatomic, readwrite) CEVAlignmentDecision decision;
@property(nonatomic, readwrite) double score;
@property(nonatomic, readwrite) double overlapRatio;
@property(nonatomic, readwrite) double reprojectionRMSE;
@property(nonatomic, readwrite) double edgeAlignmentError;
@property(nonatomic, copy, readwrite) NSString *selectedModel;
@property(nonatomic, copy, readwrite) NSArray<NSString *> *reasonCodes;
@property(nonatomic, copy, readwrite) NSArray<NSNumber *> *transform3x3;
@property(nonatomic, copy, readwrite) NSArray<NSNumber *> *validRegion;
@end

@implementation CEVClipAlignmentResult
@end

@implementation CameraeVisionClipAlignmentEstimator

+ (nullable CEVClipAlignmentResult *)estimateReferencePixelBuffer:(CVPixelBufferRef)referenceBuffer
                                              referenceOrientation:(CEVImageOrientation)referenceOrientation
                                                movingPixelBuffer:(CVPixelBufferRef)movingBuffer
                                                 movingOrientation:(CEVImageOrientation)movingOrientation
                                                              error:(NSError **)error {
    if (error) { *error = nil; }
    cv::Mat reference;
    cv::Mat moving;
    if (!BufferToMat(referenceBuffer, referenceOrientation, reference, error) ||
        !BufferToMat(movingBuffer, movingOrientation, moving, error)) {
        return nil;
    }

    try {
        const auto translation = TryModel(
            reference, moving, camerae_vision::AlignmentMotionModel::Translation);
        const auto similarity = TryModel(
            reference, moving, camerae_vision::AlignmentMotionModel::Similarity);
        if (!translation && !similarity) {
            if (error) {
                *error = MakeClipError(CameraeVisionErrorEvaluationFailed,
                                       @"Nenhum modelo conservador conseguiu alinhar os frames.");
            }
            return nil;
        }

        const camerae_vision::AlignmentResult *selected = translation ? &*translation : &*similarity;
        camerae_vision::AlignmentMotionModel model = translation ?
            camerae_vision::AlignmentMotionModel::Translation :
            camerae_vision::AlignmentMotionModel::Similarity;
        if (similarity) {
            const bool betterDecision = !translation ||
                DecisionRank(similarity->feasibility.decision) >
                DecisionRank(translation->feasibility.decision);
            const bool materiallyLowerError = translation &&
                DecisionRank(similarity->feasibility.decision) ==
                    DecisionRank(translation->feasibility.decision) &&
                similarity->metrics.edgeAlignmentError <
                    translation->metrics.edgeAlignmentError * 0.75;
            if (betterDecision || materiallyLowerError) {
                selected = &*similarity;
                model = camerae_vision::AlignmentMotionModel::Similarity;
            }
        }

        CEVClipAlignmentResult *result = [[CEVClipAlignmentResult alloc] init];
        result.schemaVersion = 1;
        result.decision = MapDecision(selected->feasibility.decision);
        result.score = selected->feasibility.score;
        result.overlapRatio = selected->metrics.overlapRatio;
        result.reprojectionRMSE = selected->metrics.reprojectionRMSE;
        result.edgeAlignmentError = selected->metrics.edgeAlignmentError;
        result.selectedModel = [NSString stringWithUTF8String:
            camerae_vision::alignmentMotionModelName(model).c_str()];
        result.reasonCodes = ReasonCodes(*selected);
        result.transform3x3 = NormalizedTransform(selected->transform, selected->validMask.size());
        result.validRegion = ValidRegion(selected->validMask);
        return result;
    } catch (const std::exception &exception) {
        if (error) {
            *error = MakeClipError(CameraeVisionErrorEvaluationFailed,
                                   [NSString stringWithUTF8String:exception.what()]);
        }
        return nil;
    }
}

@end
