#import "OpenCVBridge.h"

#import <opencv2/core.hpp>
#import <opencv2/imgcodecs/ios.h>
#import <opencv2/imgproc.hpp>
#import <opencv2/photo.hpp>
#import <opencv2/video.hpp>
#import <UIKit/UIKit.h>

namespace {

NSError *CameraeOpenCVError(NSString *message) {
    return [NSError errorWithDomain:@"Camerae.OpenCV"
                               code:1
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

bool Fail(NSError **error, NSString *message) {
    if (error != nullptr) {
        *error = CameraeOpenCVError(message);
    }
    return false;
}

cv::Mat ResizeToMaxDimension(const cv::Mat &image, int maxDimension) {
    if (maxDimension <= 0) {
        return image;
    }

    const int longest = std::max(image.cols, image.rows);
    if (longest <= maxDimension) {
        return image;
    }

    const double scale = static_cast<double>(maxDimension) / static_cast<double>(longest);
    cv::Mat resized;
    cv::resize(image, resized, cv::Size(), scale, scale, cv::INTER_AREA);
    return resized;
}

cv::Mat AlignmentGray(const cv::Mat &bgr, int maxDimension) {
    cv::Mat small = ResizeToMaxDimension(bgr, maxDimension);
    cv::Mat gray;
    cv::cvtColor(small, gray, cv::COLOR_BGR2GRAY);
    gray.convertTo(gray, CV_32F, 1.0 / 255.0);
    cv::GaussianBlur(gray, gray, cv::Size(3, 3), 0);
    return gray;
}

cv::Mat AlignFrame(const cv::Mat &referenceGray, const cv::Mat &frame, int alignDimension) {
    cv::Mat frameGray = AlignmentGray(frame, alignDimension);
    if (referenceGray.empty() || frameGray.empty() || referenceGray.size() != frameGray.size()) {
        return frame;
    }

    double response = 0;
    cv::Point2d shift = cv::phaseCorrelate(referenceGray, frameGray, cv::noArray(), &response);
    const double maxShiftX = static_cast<double>(frameGray.cols) * 0.18;
    const double maxShiftY = static_cast<double>(frameGray.rows) * 0.18;
    if (response < 0.08 ||
        std::abs(shift.x) > maxShiftX ||
        std::abs(shift.y) > maxShiftY) {
        return frame;
    }

    const double scaleX = static_cast<double>(frame.cols) / static_cast<double>(frameGray.cols);
    const double scaleY = static_cast<double>(frame.rows) / static_cast<double>(frameGray.rows);
    cv::Mat warp = cv::Mat::eye(2, 3, CV_32F);
    warp.at<float>(0, 2) = static_cast<float>(-shift.x * scaleX);
    warp.at<float>(1, 2) = static_cast<float>(-shift.y * scaleY);

    cv::Mat aligned;
    cv::warpAffine(
        frame,
        aligned,
        warp,
        cv::Size(frame.cols, frame.rows),
        cv::INTER_LINEAR,
        cv::BORDER_REFLECT
    );
    return aligned;
}

void ApplyHighlightShadow(cv::Mat &image, float shadowAmount, float highlightAmount) {
    const float shadows = std::max(0.0f, std::min(0.6f, shadowAmount)) * 0.35f;
    const float highlightDampen = std::max(0.0f, std::min(0.35f, 1.0f - highlightAmount)) * 0.45f;

    std::vector<cv::Mat> channels;
    cv::split(image, channels);
    for (cv::Mat &channel : channels) {
        cv::Mat inv = 1.0 - channel;
        cv::Mat shadowLift;
        cv::multiply(channel, inv, shadowLift);
        channel += shadowLift * shadows;

        cv::Mat highlights;
        cv::multiply(channel, channel, highlights);
        channel -= highlights * highlightDampen;
        cv::min(channel, 1.0, channel);
        cv::max(channel, 0.0, channel);
    }
    cv::merge(channels, image);
}

void ApplyGamma(cv::Mat &image, float gamma) {
    const float power = std::max(0.2f, std::min(3.0f, gamma));
    cv::max(image, 0.0, image);
    cv::pow(image, power, image);
}

void ApplySaturationAndVibrance(cv::Mat &image, float saturation, float vibrance) {
    cv::Mat hsv;
    cv::cvtColor(image, hsv, cv::COLOR_BGR2HSV);
    std::vector<cv::Mat> channels;
    cv::split(hsv, channels);

    const float sat = std::max(0.0f, std::min(2.5f, saturation));
    const float vib = std::max(-1.0f, std::min(1.0f, vibrance));
    cv::Mat lowSaturationBoost = (1.0 - channels[1]) * vib;
    channels[1] = channels[1].mul(1.0 + lowSaturationBoost);
    channels[1] *= sat;
    cv::min(channels[1], 1.0, channels[1]);
    cv::max(channels[1], 0.0, channels[1]);

    cv::merge(channels, hsv);
    cv::cvtColor(hsv, image, cv::COLOR_HSV2BGR);
}

void ApplyUnsharp(cv::Mat &image, float amount, float radius) {
    if (amount <= 0.001f || radius <= 0.1f) {
        return;
    }

    cv::Mat blurred;
    cv::GaussianBlur(image, blurred, cv::Size(0, 0), radius);
    cv::addWeighted(image, 1.0 + amount, blurred, -amount, 0.0, image);
    cv::min(image, 1.0, image);
    cv::max(image, 0.0, image);
}

cv::Mat ToUInt8(const cv::Mat &floatImage) {
    cv::Mat clamped;
    cv::min(floatImage, 1.0, clamped);
    cv::max(clamped, 0.0, clamped);
    cv::Mat output;
    clamped.convertTo(output, CV_8UC3, 255.0);
    return output;
}

UIImage *NormalizedImage(UIImage *image) {
    if (image.imageOrientation == UIImageOrientationUp) {
        return image;
    }

    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
    format.scale = image.scale;
    format.opaque = NO;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:image.size format:format];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [image drawInRect:CGRectMake(0, 0, image.size.width, image.size.height)];
    }];
}

cv::Mat LoadImage(NSString *path) {
    UIImage *image = [UIImage imageWithContentsOfFile:path];
    if (image == nil) {
        return cv::Mat();
    }

    image = NormalizedImage(image);

    cv::Mat mat;
    UIImageToMat(image, mat);
    if (mat.empty()) {
        return mat;
    }

    if (mat.channels() == 4) {
        cv::cvtColor(mat, mat, cv::COLOR_RGBA2BGR);
    } else if (mat.channels() == 1) {
        cv::cvtColor(mat, mat, cv::COLOR_GRAY2BGR);
    }
    return mat;
}

void NormalizeExposureAndWhiteBalance(cv::Mat &bgr) {
    cv::Mat small = ResizeToMaxDimension(bgr, 96);
    cv::Scalar mean = cv::mean(small);
    const double blue = std::max(1.0, mean[0]);
    const double green = std::max(1.0, mean[1]);
    const double red = std::max(1.0, mean[2]);
    const double luma = (0.2126 * red + 0.7152 * green + 0.0722 * blue) / 255.0;
    const double exposureRatio = std::max(0.5, std::min(2.5, 0.30 / std::max(0.01, luma)));
    const double gray = std::max(1.0, (red + green + blue) / 3.0);
    const double redGain = std::max(0.90, std::min(1.10, gray / red));
    const double greenGain = std::max(0.92, std::min(1.08, gray / green));
    const double blueGain = std::max(0.90, std::min(1.12, gray / blue));

    cv::Mat floatImage;
    bgr.convertTo(floatImage, CV_32FC3, 1.0 / 255.0);
    std::vector<cv::Mat> channels;
    cv::split(floatImage, channels);
    channels[0] *= static_cast<float>(blueGain * exposureRatio);
    channels[1] *= static_cast<float>(greenGain * exposureRatio);
    channels[2] *= static_cast<float>(redGain * exposureRatio);
    cv::merge(channels, floatImage);
    bgr = ToUInt8(floatImage);
}

bool SaveJPEG(const cv::Mat &bgr, NSString *path, NSError **error) {
    cv::Mat rgba;
    cv::cvtColor(bgr, rgba, cv::COLOR_BGR2RGBA);
    UIImage *image = MatToUIImage(rgba);
    NSData *data = UIImageJPEGRepresentation(image, 0.95);
    if (data == nil) {
        return Fail(error, @"Nao foi possivel codificar o JPEG processado.");
    }

    if (![data writeToFile:path options:NSDataWritingAtomic error:error]) {
        return false;
    }
    return true;
}

}

@implementation OpenCVBridge

+ (NSString *)versionString {
#ifdef CV_VERSION
    return [NSString stringWithUTF8String:CV_VERSION];
#else
    return @"unknown";
#endif
}

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
                              error:(NSError **)error {
    if (framePaths.count == 0) {
        return Fail(error, @"Nenhum frame para processar.");
    }

    cv::Mat accumulator;
    cv::Mat referenceGray;
    cv::Size targetSize;
    int framesUsed = 0;
    const int outputMaxDimension = static_cast<int>(maxDimension);
    const int alignDimension = 768;

    for (NSString *path in framePaths) {
        @autoreleasepool {
            cv::Mat frame = LoadImage(path);
            if (frame.empty()) {
                return Fail(error, [NSString stringWithFormat:@"Nao foi possivel abrir %@", path.lastPathComponent]);
            }

            frame = ResizeToMaxDimension(frame, outputMaxDimension);
            if (normalizeFrames) {
                NormalizeExposureAndWhiteBalance(frame);
            }

            if (framesUsed == 0) {
                targetSize = frame.size();
                referenceGray = AlignmentGray(frame, alignDimension);
                accumulator = cv::Mat::zeros(frame.rows, frame.cols, CV_32FC3);
            } else if (frame.size() != targetSize) {
                cv::resize(frame, frame, targetSize, 0, 0, cv::INTER_AREA);
            }

            if (alignStars && framesUsed > 0) {
                frame = AlignFrame(referenceGray, frame, alignDimension);
            }

            cv::Mat floatFrame;
            frame.convertTo(floatFrame, CV_32FC3, 1.0 / 255.0);
            accumulator += floatFrame;
            framesUsed += 1;
        }
    }

    if (framesUsed == 0 || accumulator.empty()) {
        return Fail(error, @"Nenhum frame valido foi processado.");
    }

    cv::Mat output = accumulator / static_cast<float>(framesUsed);
    ApplyHighlightShadow(output, shadowAmount, highlightAmount);
    ApplyGamma(output, gamma);
    ApplySaturationAndVibrance(output, saturation, vibrance);
    output.convertTo(output, -1, contrast, brightness);
    cv::min(output, 1.0, output);
    cv::max(output, 0.0, output);
    ApplyUnsharp(output, unsharpAmount, unsharpRadius);

    cv::Mat finalImage = ToUInt8(output);
    if (denoise) {
        const float strength = std::max(0.5f, std::min(15.0f, denoiseStrength));
        cv::fastNlMeansDenoisingColored(finalImage, finalImage, strength, strength, 7, 21);
    }

    try {
        if (!SaveJPEG(finalImage, outputPath, error)) {
            return Fail(error, @"Nao foi possivel salvar o JPEG processado.");
        }
    } catch (const cv::Exception &exception) {
        NSString *message = [NSString stringWithFormat:@"OpenCV falhou ao salvar: %s", exception.what()];
        return Fail(error, message);
    }

    return true;
}

@end
