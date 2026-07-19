#import "CameraeVisionRuntime.h"

#include "camerae_vision/capture_alignment_session.hpp"
#include "camerae_vision/diagnostics.hpp"

#include <opencv2/core.hpp>
#include <opencv2/imgproc.hpp>

@implementation CameraeVisionRuntime

+ (NSString *)versionString {
    return [NSString stringWithFormat:@"CameraeVision schema=%d OpenCV=%s",
                                      camerae_vision::cameraeVisionDiagnosticsSchemaVersion,
                                      CV_VERSION];
}

+ (BOOL)runSmokeTestWithError:(NSError **)error {
    try {
        cv::Mat reference(160, 240, CV_8UC3);
        cv::RNG random(0xCA4E);
        random.fill(reference, cv::RNG::UNIFORM, 0, 255);
        cv::rectangle(reference, cv::Rect(40, 30, 80, 60), cv::Scalar(10, 240, 80), 3);

        camerae_vision::CaptureAlignmentSession session(reference);
        std::optional<camerae_vision::CaptureAlignmentQuality> result = session.evaluate(reference);
        if (!result.has_value()) {
            if (error != nullptr) {
                *error = [NSError errorWithDomain:@"Camerae.Vision"
                                             code:1
                                         userInfo:@{NSLocalizedDescriptionKey: @"CaptureFast returned no result."}];
            }
            return NO;
        }
        return YES;
    } catch (const std::exception &exception) {
        if (error != nullptr) {
            *error = [NSError errorWithDomain:@"Camerae.Vision"
                                         code:2
                                     userInfo:@{NSLocalizedDescriptionKey:
                                         [NSString stringWithUTF8String:exception.what()]}];
        }
        return NO;
    }
}

@end
