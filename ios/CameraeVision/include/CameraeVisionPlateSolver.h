#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, CameraeVisionPlateSolveStatus) {
    CameraeVisionPlateSolveStatusDetectionCompleted,
    CameraeVisionPlateSolveStatusSolved,
    CameraeVisionPlateSolveStatusNotSolved,
};

@interface CameraeVisionPlateSolveResult : NSObject

@property (nonatomic, readonly) CameraeVisionPlateSolveStatus status;
@property (nonatomic, readonly) NSInteger detectedStarCount;
@property (nonatomic, readonly) NSTimeInterval detectionDuration;
@property (nonatomic, readonly) double rightAscensionDegrees;
@property (nonatomic, readonly) double declinationDegrees;
@property (nonatomic, readonly) double rollDegrees;
@property (nonatomic, readonly) double horizontalFieldOfViewDegrees;
@property (nonatomic, readonly) double rootMeanSquareErrorPixels;
@property (nonatomic, readonly) NSInteger matchedStarCount;
@property (nonatomic, readonly) double confidence;
@property (nonatomic, readonly, getter=isParityInverted) BOOL parityInverted;

@end

@interface CameraeVisionPlateSolver : NSObject

+ (nullable CameraeVisionPlateSolveResult *)detectImageAtURL:(NSURL *)imageURL
                                                       error:(NSError **)error;

+ (nullable CameraeVisionPlateSolveResult *)solveImageAtURL:(NSURL *)imageURL
                                          compactCatalogURL:(NSURL *)catalogURL
                    approximateHorizontalFieldOfViewDegrees:(double)fieldOfViewDegrees
                                             minimumMatches:(NSInteger)minimumMatches
                                                      error:(NSError **)error;

+ (nullable CameraeVisionPlateSolveResult *)solveImageAtURL:(NSURL *)imageURL
                                          compactCatalogURL:(NSURL *)catalogURL
                          approximateRightAscensionDegrees:(double)rightAscensionDegrees
                              approximateDeclinationDegrees:(double)declinationDegrees
                    approximateHorizontalFieldOfViewDegrees:(double)fieldOfViewDegrees
                                             minimumMatches:(NSInteger)minimumMatches
                                                      error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
