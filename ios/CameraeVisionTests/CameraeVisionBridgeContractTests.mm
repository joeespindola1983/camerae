#import <CameraeVision/CameraeVision.h>
#import <CoreVideo/CoreVideo.h>
#import <XCTest/XCTest.h>

@interface CameraeVisionBridgeContractTests : XCTestCase
@end

@implementation CameraeVisionBridgeContractTests

- (void)testBGRAReferenceAndMovingFrameReturnTypedResultWithTransform {
    CVPixelBufferRef reference = [self makeTexturedBGRAWithWidth:241 height:173 seed:17];
    XCTAssertNotEqual(reference, nil);
    XCTAssertGreaterThan(CVPixelBufferGetBytesPerRow(reference), 241 * 4);

    NSError *error = nil;
    CameraeVisionCaptureSession *session = [[CameraeVisionCaptureSession alloc]
        initWithReferencePixelBuffer:reference
        orientation:CEVImageOrientationUp
        error:&error];
    XCTAssertNotNil(session, @"%@", error);

    CEVCaptureAlignmentResult *result = [session evaluatePixelBuffer:reference
                                                         orientation:CEVImageOrientationUp
                                                               error:&error];
    XCTAssertNotNil(result, @"%@", error);
    XCTAssertEqual(result.schemaVersion, 1);
    XCTAssertEqual(result.transform3x3.count, 9);
    XCTAssertTrue(result.decision == CEVAlignmentDecisionAccept ||
                  result.decision == CEVAlignmentDecisionReview);
    XCTAssertGreaterThan(result.score, 0);
    XCTAssertEqualObjects(result.selectedModel, @"similarity");

    CVPixelBufferRelease(reference);
}

- (void)testUnsupportedPixelFormatReturnsStableError {
    NSDictionary *attributes = @{(NSString *)kCVPixelBufferIOSurfacePropertiesKey: @{}};
    CVPixelBufferRef grayscale = nil;
    XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, 80, 80,
                                       kCVPixelFormatType_OneComponent8,
                                       (__bridge CFDictionaryRef)attributes,
                                       &grayscale), kCVReturnSuccess);

    NSError *error = nil;
    CameraeVisionCaptureSession *session = [[CameraeVisionCaptureSession alloc]
        initWithReferencePixelBuffer:grayscale
        orientation:CEVImageOrientationUp
        error:&error];
    XCTAssertNil(session);
    XCTAssertEqualObjects(error.domain, CameraeVisionErrorDomain);
    XCTAssertEqual(error.code, CameraeVisionErrorUnsupportedPixelFormat);
    CVPixelBufferRelease(grayscale);
}

- (void)testCancelledSessionReturnsBeforeEvaluationAndCanResume {
    CVPixelBufferRef reference = [self makeTexturedBGRAWithWidth:160 height:120 seed:29];
    NSError *error = nil;
    CameraeVisionCaptureSession *session = [[CameraeVisionCaptureSession alloc]
        initWithReferencePixelBuffer:reference
        orientation:CEVImageOrientationRight
        error:&error];
    XCTAssertNotNil(session, @"%@", error);

    [session cancel];
    XCTAssertNil([session evaluatePixelBuffer:reference
                                  orientation:CEVImageOrientationRight
                                        error:&error]);
    XCTAssertEqual(error.code, CameraeVisionErrorCancelled);

    [session resume];
    XCTAssertNotNil([session evaluatePixelBuffer:reference
                                     orientation:CEVImageOrientationRight
                                           error:&error], @"%@", error);
    CVPixelBufferRelease(reference);
}

- (void)testReferenceUpdateInvalidatesPreparedFeaturesOnce {
    CVPixelBufferRef first = [self makeTexturedBGRAWithWidth:180 height:120 seed:31];
    CVPixelBufferRef second = [self makeTexturedBGRAWithWidth:180 height:120 seed:47];
    NSError *error = nil;
    CameraeVisionCaptureSession *session = [[CameraeVisionCaptureSession alloc]
        initWithReferencePixelBuffer:first
        orientation:CEVImageOrientationUp
        error:&error];

    XCTAssertNotNil([session evaluatePixelBuffer:first orientation:CEVImageOrientationUp error:&error]);
    XCTAssertTrue([session updateReferencePixelBuffer:second
                                         orientation:CEVImageOrientationDown
                                               error:&error]);
    XCTAssertNotNil([session evaluatePixelBuffer:second orientation:CEVImageOrientationDown error:&error]);
    XCTAssertEqual(session.diagnostics.referenceUpdates, 1);
    XCTAssertEqual(session.diagnostics.referenceFeatureExtractions, 2);

    CVPixelBufferRelease(first);
    CVPixelBufferRelease(second);
}

- (CVPixelBufferRef)makeTexturedBGRAWithWidth:(size_t)width
                                        height:(size_t)height
                                          seed:(uint32_t)seed CF_RETURNS_RETAINED {
    NSDictionary *attributes = @{(NSString *)kCVPixelBufferIOSurfacePropertiesKey: @{}};
    CVPixelBufferRef pixelBuffer = nil;
    CVReturn status = CVPixelBufferCreate(kCFAllocatorDefault, width, height,
                                          kCVPixelFormatType_32BGRA,
                                          (__bridge CFDictionaryRef)attributes,
                                          &pixelBuffer);
    if (status != kCVReturnSuccess) { return nil; }

    CVPixelBufferLockBaseAddress(pixelBuffer, 0);
    uint8_t *base = (uint8_t *)CVPixelBufferGetBaseAddress(pixelBuffer);
    const size_t bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer);
    uint32_t state = seed;
    for (size_t row = 0; row < height; ++row) {
        uint8_t *pixels = base + row * bytesPerRow;
        for (size_t column = 0; column < width; ++column) {
            state = state * 1664525u + 1013904223u;
            pixels[column * 4 + 0] = (uint8_t)(state & 0xff);
            pixels[column * 4 + 1] = (uint8_t)((state >> 8) & 0xff);
            pixels[column * 4 + 2] = (uint8_t)((state >> 16) & 0xff);
            pixels[column * 4 + 3] = 255;
        }
    }
    CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
    return pixelBuffer;
}

@end
