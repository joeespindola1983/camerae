#import <CameraeVision/CameraeVisionCaptureSession.h>
#import <CoreVideo/CoreVideo.h>
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface CEVClipAlignmentResult : NSObject

@property(nonatomic, readonly) NSInteger schemaVersion;
@property(nonatomic, readonly) CEVAlignmentDecision decision;
@property(nonatomic, readonly) double score;
@property(nonatomic, readonly) double overlapRatio;
@property(nonatomic, readonly) double reprojectionRMSE;
@property(nonatomic, readonly) double edgeAlignmentError;
@property(nonatomic, copy, readonly) NSString *selectedModel;
@property(nonatomic, copy, readonly) NSArray<NSString *> *reasonCodes;
/// Row-major transform from normalized moving coordinates to normalized reference coordinates.
@property(nonatomic, copy, readonly) NSArray<NSNumber *> *transform3x3;
/// Normalized axis-aligned valid region: x, y, width, height.
@property(nonatomic, copy, readonly) NSArray<NSNumber *> *validRegion;

@end

@interface CameraeVisionClipAlignmentEstimator : NSObject

+ (nullable CEVClipAlignmentResult *)estimateReferencePixelBuffer:(CVPixelBufferRef)reference
                                              referenceOrientation:(CEVImageOrientation)referenceOrientation
                                                movingPixelBuffer:(CVPixelBufferRef)moving
                                                 movingOrientation:(CEVImageOrientation)movingOrientation
                                                              error:(NSError **)error
    NS_SWIFT_NAME(estimate(reference:referenceOrientation:moving:movingOrientation:));

@end

NS_ASSUME_NONNULL_END
