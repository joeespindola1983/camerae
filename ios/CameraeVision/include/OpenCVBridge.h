#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface OpenCVBridge : NSObject

+ (NSString *)versionString;
+ (BOOL)renderStackWithFramePaths:(NSArray<NSString *> *)framePaths
                        outputPath:(NSString *)outputPath
                      maxDimension:(NSInteger)maxDimension
                        alignStars:(BOOL)alignStars
                   normalizeFrames:(BOOL)normalizeFrames
                            denoise:(BOOL)denoise
                   denoiseStrength:(float)denoiseStrength
                              gamma:(float)gamma
                           contrast:(float)contrast
                         brightness:(float)brightness
                         saturation:(float)saturation
                      shadowAmount:(float)shadowAmount
                   highlightAmount:(float)highlightAmount
                           vibrance:(float)vibrance
                      unsharpAmount:(float)unsharpAmount
                      unsharpRadius:(float)unsharpRadius
                              error:(NSError **)error
NS_SWIFT_NAME(renderStack(framePaths:outputPath:maxDimension:alignStars:normalizeFrames:denoise:denoiseStrength:gamma:contrast:brightness:saturation:shadowAmount:highlightAmount:vibrance:unsharpAmount:unsharpRadius:));

@end

NS_ASSUME_NONNULL_END
