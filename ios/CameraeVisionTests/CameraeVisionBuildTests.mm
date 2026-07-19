#import <CameraeVision/CameraeVision.h>
#import <XCTest/XCTest.h>

@interface CameraeVisionBuildTests : XCTestCase
@end

@implementation CameraeVisionBuildTests

- (void)testRuntimeUsesPinnedOpenCVVersion {
    XCTAssertTrue([[CameraeVisionRuntime versionString] containsString:@"OpenCV=4.13.0"]);
}

- (void)testCaptureFastSmokeTestRunsOnCurrentPlatform {
    NSError *error = nil;
    XCTAssertTrue([CameraeVisionRuntime runSmokeTestWithError:&error], @"%@", error);
}

@end
