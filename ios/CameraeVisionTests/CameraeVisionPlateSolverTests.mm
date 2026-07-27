#import <XCTest/XCTest.h>
#import <CameraeVision/CameraeVision.h>

@interface CameraeVisionPlateSolverTests : XCTestCase
@end

@implementation CameraeVisionPlateSolverTests

- (void)testMissingImageIsRejectedWithoutProducingASolution {
    NSURL *missing = [NSURL fileURLWithPath:@"/tmp/camerae-missing-plate.png"];
    NSError *error = nil;
    CameraeVisionPlateSolveResult *result =
        [CameraeVisionPlateSolver detectImageAtURL:missing error:&error];

    XCTAssertNil(result);
    XCTAssertNotNil(error);
    XCTAssertEqualObjects(error.domain, @"Camerae.Vision.PlateSolving");
}

@end
