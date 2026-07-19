#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface CameraeVisionRuntime : NSObject

+ (NSString *)versionString;
+ (BOOL)runSmokeTestWithError:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
