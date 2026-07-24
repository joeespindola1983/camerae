#import <CameraeVision/CameraeVision.h>
#import <CoreVideo/CoreVideo.h>
#import <XCTest/XCTest.h>

@interface CameraeVisionClipAlignmentTests : XCTestCase
@end

@implementation CameraeVisionClipAlignmentTests

- (void)testKnownTranslationReturnsNormalizedConservativeClipTransform {
    CVPixelBufferRef reference = [self makeTexturedBufferWithWidth:240 height:180 seed:71];
    CVPixelBufferRef moving = [self makeShiftedCopy:reference shiftX:12 shiftY:-6];

    NSError *error = nil;
    CEVClipAlignmentResult *result = [CameraeVisionClipAlignmentEstimator
        estimateReferencePixelBuffer:reference
        referenceOrientation:CEVImageOrientationUp
        movingPixelBuffer:moving
        movingOrientation:CEVImageOrientationUp
        error:&error];

    XCTAssertNotNil(result, @"%@", error);
    XCTAssertEqual(result.schemaVersion, 1);
    XCTAssertEqualObjects(result.selectedModel, @"translation");
    XCTAssertEqual(result.transform3x3.count, 9);
    XCTAssertEqual(result.validRegion.count, 4);
    XCTAssertEqualWithAccuracy(result.transform3x3[2].doubleValue, -0.05, 0.025);
    XCTAssertEqualWithAccuracy(result.transform3x3[5].doubleValue, 6.0 / 180.0, 0.025);
    XCTAssertGreaterThan(result.score, 0.5);
    XCTAssertTrue(result.decision == CEVAlignmentDecisionAccept ||
                  result.decision == CEVAlignmentDecisionReview);

    CVPixelBufferRelease(reference);
    CVPixelBufferRelease(moving);
}

- (void)testUnsupportedMovingPixelFormatReturnsTypedError {
    CVPixelBufferRef reference = [self makeTexturedBufferWithWidth:80 height:80 seed:11];
    CVPixelBufferRef grayscale = nil;
    CVPixelBufferCreate(kCFAllocatorDefault, 80, 80, kCVPixelFormatType_OneComponent8,
                        NULL, &grayscale);
    NSError *error = nil;

    XCTAssertNil([CameraeVisionClipAlignmentEstimator
        estimateReferencePixelBuffer:reference
        referenceOrientation:CEVImageOrientationUp
        movingPixelBuffer:grayscale
        movingOrientation:CEVImageOrientationUp
        error:&error]);
    XCTAssertEqual(error.code, CameraeVisionErrorUnsupportedPixelFormat);

    CVPixelBufferRelease(reference);
    CVPixelBufferRelease(grayscale);
}

- (void)testRotationReportsAnInscribedValidRegionWithoutBlackCornerWedges {
    CVPixelBufferRef reference = [self makeTexturedBufferWithWidth:320 height:240 seed:97];
    CVPixelBufferRef moving = [self makeRotatedCopy:reference degrees:4.0];
    NSError *error = nil;

    CEVClipAlignmentResult *result = [CameraeVisionClipAlignmentEstimator
        estimateReferencePixelBuffer:reference
        referenceOrientation:CEVImageOrientationUp
        movingPixelBuffer:moving
        movingOrientation:CEVImageOrientationUp
        error:&error];

    XCTAssertNotNil(result, @"%@", error);
    XCTAssertEqualObjects(result.selectedModel, @"similarity");
    XCTAssertGreaterThan(result.validRegion[0].doubleValue, 0.0);
    XCTAssertGreaterThan(result.validRegion[1].doubleValue, 0.0);
    XCTAssertLessThan(result.validRegion[2].doubleValue, 0.99);
    XCTAssertLessThan(result.validRegion[3].doubleValue, 0.99);

    CVPixelBufferRelease(reference);
    CVPixelBufferRelease(moving);
}

- (CVPixelBufferRef)makeTexturedBufferWithWidth:(size_t)width
                                         height:(size_t)height
                                           seed:(uint32_t)seed CF_RETURNS_RETAINED {
    CVPixelBufferRef buffer = nil;
    NSDictionary *attributes = @{(NSString *)kCVPixelBufferIOSurfacePropertiesKey: @{}};
    CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
                        (__bridge CFDictionaryRef)attributes, &buffer);
    CVPixelBufferLockBaseAddress(buffer, 0);
    uint8_t *base = (uint8_t *)CVPixelBufferGetBaseAddress(buffer);
    const size_t stride = CVPixelBufferGetBytesPerRow(buffer);
    uint32_t state = seed;
    for (size_t y = 0; y < height; ++y) {
        for (size_t x = 0; x < width; ++x) {
            state = state * 1664525u + 1013904223u;
            uint8_t *pixel = base + y * stride + x * 4;
            pixel[0] = (uint8_t)state;
            pixel[1] = (uint8_t)(state >> 8);
            pixel[2] = (uint8_t)(state >> 16);
            pixel[3] = 255;
        }
    }
    CVPixelBufferUnlockBaseAddress(buffer, 0);
    return buffer;
}

- (CVPixelBufferRef)makeShiftedCopy:(CVPixelBufferRef)source
                             shiftX:(int)shiftX
                             shiftY:(int)shiftY CF_RETURNS_RETAINED {
    const size_t width = CVPixelBufferGetWidth(source);
    const size_t height = CVPixelBufferGetHeight(source);
    CVPixelBufferRef output = nil;
    NSDictionary *attributes = @{(NSString *)kCVPixelBufferIOSurfacePropertiesKey: @{}};
    CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
                        (__bridge CFDictionaryRef)attributes, &output);
    CVPixelBufferLockBaseAddress(source, kCVPixelBufferLock_ReadOnly);
    CVPixelBufferLockBaseAddress(output, 0);
    uint8_t *sourceBase = (uint8_t *)CVPixelBufferGetBaseAddress(source);
    uint8_t *outputBase = (uint8_t *)CVPixelBufferGetBaseAddress(output);
    const size_t sourceStride = CVPixelBufferGetBytesPerRow(source);
    const size_t outputStride = CVPixelBufferGetBytesPerRow(output);
    memset(outputBase, 0, outputStride * height);
    for (int y = 0; y < (int)height; ++y) {
        for (int x = 0; x < (int)width; ++x) {
            const int sourceX = x - shiftX;
            const int sourceY = y - shiftY;
            if (sourceX < 0 || sourceY < 0 || sourceX >= (int)width || sourceY >= (int)height) {
                continue;
            }
            memcpy(outputBase + y * outputStride + x * 4,
                   sourceBase + sourceY * sourceStride + sourceX * 4, 4);
        }
    }
    CVPixelBufferUnlockBaseAddress(output, 0);
    CVPixelBufferUnlockBaseAddress(source, kCVPixelBufferLock_ReadOnly);
    return output;
}

- (CVPixelBufferRef)makeRotatedCopy:(CVPixelBufferRef)source
                            degrees:(double)degrees CF_RETURNS_RETAINED {
    const size_t width = CVPixelBufferGetWidth(source);
    const size_t height = CVPixelBufferGetHeight(source);
    CVPixelBufferRef output = nil;
    NSDictionary *attributes = @{(NSString *)kCVPixelBufferIOSurfacePropertiesKey: @{}};
    CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
                        (__bridge CFDictionaryRef)attributes, &output);
    CVPixelBufferLockBaseAddress(source, kCVPixelBufferLock_ReadOnly);
    CVPixelBufferLockBaseAddress(output, 0);
    uint8_t *sourceBase = (uint8_t *)CVPixelBufferGetBaseAddress(source);
    uint8_t *outputBase = (uint8_t *)CVPixelBufferGetBaseAddress(output);
    const size_t sourceStride = CVPixelBufferGetBytesPerRow(source);
    const size_t outputStride = CVPixelBufferGetBytesPerRow(output);
    memset(outputBase, 0, outputStride * height);
    const double radians = degrees * M_PI / 180.0;
    const double cosine = cos(radians);
    const double sine = sin(radians);
    const double centerX = ((double)width - 1.0) / 2.0;
    const double centerY = ((double)height - 1.0) / 2.0;
    for (int y = 0; y < (int)height; ++y) {
        for (int x = 0; x < (int)width; ++x) {
            const double centeredX = x - centerX;
            const double centeredY = y - centerY;
            const int sourceX = (int)llround(
                cosine * centeredX + sine * centeredY + centerX
            );
            const int sourceY = (int)llround(
                -sine * centeredX + cosine * centeredY + centerY
            );
            if (sourceX < 0 || sourceY < 0 ||
                sourceX >= (int)width || sourceY >= (int)height) {
                continue;
            }
            memcpy(outputBase + y * outputStride + x * 4,
                   sourceBase + sourceY * sourceStride + sourceX * 4, 4);
        }
    }
    CVPixelBufferUnlockBaseAddress(output, 0);
    CVPixelBufferUnlockBaseAddress(source, kCVPixelBufferLock_ReadOnly);
    return output;
}

@end
