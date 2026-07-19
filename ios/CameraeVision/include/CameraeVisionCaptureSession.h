#import <CoreVideo/CoreVideo.h>
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSErrorDomain const CameraeVisionErrorDomain;

typedef NS_ERROR_ENUM(CameraeVisionErrorDomain, CameraeVisionErrorCode) {
    CameraeVisionErrorInvalidInput = 1,
    CameraeVisionErrorUnsupportedPixelFormat = 2,
    CameraeVisionErrorPixelBufferLockFailed = 3,
    CameraeVisionErrorEvaluationFailed = 4,
    CameraeVisionErrorCancelled = 5,
};

typedef NS_ENUM(NSInteger, CEVImageOrientation) {
    CEVImageOrientationUp = 0,
    CEVImageOrientationRight = 1,
    CEVImageOrientationDown = 2,
    CEVImageOrientationLeft = 3,
};

typedef NS_ENUM(NSInteger, CEVAlignmentDecision) {
    CEVAlignmentDecisionAccept = 0,
    CEVAlignmentDecisionReview = 1,
    CEVAlignmentDecisionReject = 2,
    CEVAlignmentDecisionUnavailable = 3,
};

@interface CEVCaptureAlignmentResult : NSObject

@property(nonatomic, readonly) NSInteger schemaVersion;
@property(nonatomic, readonly) CEVAlignmentDecision decision;
@property(nonatomic, readonly) double score;
@property(nonatomic, readonly) double overlapRatio;
@property(nonatomic, readonly) double reprojectionRMSE;
@property(nonatomic, readonly) double edgeAlignmentError;
@property(nonatomic, readonly) double latencyMilliseconds;
@property(nonatomic, copy, readonly) NSString *selectedModel;
@property(nonatomic, copy, readonly) NSArray<NSString *> *reasonCodes;
@property(nonatomic, copy, readonly) NSArray<NSNumber *> *transform3x3;

@end

@interface CEVCaptureAlignmentDiagnostics : NSObject

@property(nonatomic, readonly) NSUInteger completedEvaluations;
@property(nonatomic, readonly) NSUInteger cancelledEvaluations;
@property(nonatomic, readonly) NSUInteger referenceUpdates;
@property(nonatomic, readonly) NSUInteger referenceFeatureExtractions;
@property(nonatomic, readonly) NSUInteger retainedReferenceBytes;
@property(nonatomic, readonly) NSUInteger estimatedRetainedBytes;

@end

@interface CameraeVisionCaptureSession : NSObject

- (nullable instancetype)initWithReferencePixelBuffer:(CVPixelBufferRef)referencePixelBuffer
                                           orientation:(CEVImageOrientation)orientation
                                                 error:(NSError **)error NS_DESIGNATED_INITIALIZER;

- (nullable CEVCaptureAlignmentResult *)evaluatePixelBuffer:(CVPixelBufferRef)pixelBuffer
                                                 orientation:(CEVImageOrientation)orientation
                                                       error:(NSError **)error;

- (BOOL)updateReferencePixelBuffer:(CVPixelBufferRef)referencePixelBuffer
                       orientation:(CEVImageOrientation)orientation
                             error:(NSError **)error;

- (void)cancel;
- (void)resume;

@property(nonatomic, readonly) CEVCaptureAlignmentDiagnostics *diagnostics;

- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
