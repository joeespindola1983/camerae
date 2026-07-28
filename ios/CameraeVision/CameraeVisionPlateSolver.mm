#import "CameraeVisionPlateSolver.h"

#include "camerae_vision/plate_solving.hpp"

#include <opencv2/imgcodecs.hpp>

namespace {

NSString *const CameraeVisionPlateSolvingErrorDomain = @"Camerae.Vision.PlateSolving";

void assignError(NSError **error, NSInteger code, NSString *message) {
    if (error != nullptr) {
        *error = [NSError errorWithDomain:CameraeVisionPlateSolvingErrorDomain
                                     code:code
                                 userInfo:@{NSLocalizedDescriptionKey: message}];
    }
}

std::vector<std::uint8_t> catalogBytes(NSURL *url) {
    NSData *data = [NSData dataWithContentsOfURL:url];
    if (data == nil) {
        throw std::runtime_error("could not read the compact star catalog");
    }
    const auto *begin = static_cast<const std::uint8_t *>(data.bytes);
    return {begin, begin + data.length};
}

CameraeVisionPlateSolveResult *makeResult(
    const camerae_vision::plate_solving::StarDetectionResult& detection,
    const camerae_vision::plate_solving::PlateSolution *solution
);

struct PreparedImage {
    cv::Mat image;
    camerae_vision::plate_solving::StarDetectionResult detection;
};

PreparedImage prepareImage(NSURL *url) {
    const char *path = url.fileSystemRepresentation;
    const cv::Mat source = cv::imread(path, cv::IMREAD_UNCHANGED);
    if (source.empty()) {
        throw std::runtime_error("could not decode the plate-solving image");
    }
    const auto region =
        camerae_vision::plate_solving::detectActiveImageRegion(source);
    cv::Mat activeImage = source(cv::Rect(
        region.x,
        region.y,
        region.width,
        region.height
    )).clone();
    camerae_vision::plate_solving::StarDetectorSettings settings;
    auto detection =
        camerae_vision::plate_solving::detectStars(activeImage, settings);
    return {std::move(activeImage), std::move(detection)};
}

} // namespace

@interface CameraeVisionPlateSolveResult ()

@property (nonatomic, readwrite) CameraeVisionPlateSolveStatus status;
@property (nonatomic, readwrite) NSInteger detectedStarCount;
@property (nonatomic, readwrite) NSTimeInterval detectionDuration;
@property (nonatomic, readwrite) double rightAscensionDegrees;
@property (nonatomic, readwrite) double declinationDegrees;
@property (nonatomic, readwrite) double rollDegrees;
@property (nonatomic, readwrite) double horizontalFieldOfViewDegrees;
@property (nonatomic, readwrite) double rootMeanSquareErrorPixels;
@property (nonatomic, readwrite) NSInteger matchedStarCount;
@property (nonatomic, readwrite) double confidence;
@property (nonatomic, readwrite, getter=isParityInverted) BOOL parityInverted;

@end

@implementation CameraeVisionPlateSolveResult
@end

namespace {

CameraeVisionPlateSolveResult *makeResult(
    const camerae_vision::plate_solving::StarDetectionResult& detection,
    const camerae_vision::plate_solving::PlateSolution *solution
) {
    CameraeVisionPlateSolveResult *result =
        [[CameraeVisionPlateSolveResult alloc] init];
    result.detectedStarCount = detection.stars.size();
    result.detectionDuration = detection.elapsedMilliseconds / 1000.0;
    if (solution == nullptr) {
        result.status = CameraeVisionPlateSolveStatusDetectionCompleted;
        return result;
    }
    result.status = solution->status ==
            camerae_vision::plate_solving::PlateSolvingStatus::Solved
        ? CameraeVisionPlateSolveStatusSolved
        : CameraeVisionPlateSolveStatusNotSolved;
    result.rightAscensionDegrees = solution->center.rightAscensionDegrees;
    result.declinationDegrees = solution->center.declinationDegrees;
    result.rollDegrees = solution->rollDegrees;
    result.horizontalFieldOfViewDegrees =
        solution->horizontalFieldOfViewDegrees;
    result.rootMeanSquareErrorPixels =
        solution->rootMeanSquareErrorPixels;
    result.matchedStarCount = solution->matchedStars;
    result.confidence = solution->confidence;
    result.parityInverted = solution->parityInverted;
    return result;
}

} // namespace

@implementation CameraeVisionPlateSolver

+ (CameraeVisionPlateSolveResult *)detectImageAtURL:(NSURL *)imageURL
                                              error:(NSError **)error {
    try {
        const PreparedImage prepared = prepareImage(imageURL);
        return makeResult(prepared.detection, nullptr);
    } catch (const std::exception& exception) {
        assignError(
            error,
            1,
            [NSString stringWithUTF8String:exception.what()]
        );
        return nil;
    }
}

+ (CameraeVisionPlateSolveResult *)solveImageAtURL:(NSURL *)imageURL
                                 compactCatalogURL:(NSURL *)catalogURL
           approximateHorizontalFieldOfViewDegrees:(double)fieldOfViewDegrees
                                    minimumMatches:(NSInteger)minimumMatches
                                             error:(NSError **)error {
    try {
        const PreparedImage prepared = prepareImage(imageURL);
        camerae_vision::plate_solving::LostInSpacePlateSolveRequest request;
        request.detectedStars = prepared.detection.stars;
        request.imageWidth = prepared.detection.imageWidth;
        request.imageHeight = prepared.detection.imageHeight;
        request.catalog = camerae_vision::plate_solving::deserializeCompactCatalog(
            catalogBytes(catalogURL)
        );
        request.approximateHorizontalFieldOfViewDegrees = fieldOfViewDegrees;
        request.minimumMatches = static_cast<int>(minimumMatches);
        request.matchTolerancePixels = 16.0;
        const auto solution =
            camerae_vision::plate_solving::solveLostInSpace(request);
        if (solution.status ==
            camerae_vision::plate_solving::PlateSolvingStatus::InvalidInput) {
            assignError(error, 2, @"Invalid plate-solving input.");
            return nil;
        }
        return makeResult(prepared.detection, &solution);
    } catch (const std::exception& exception) {
        assignError(
            error,
            2,
            [NSString stringWithUTF8String:exception.what()]
        );
        return nil;
    }
}

+ (CameraeVisionPlateSolveResult *)solveImageAtURL:(NSURL *)imageURL
                                 compactCatalogURL:(NSURL *)catalogURL
                 approximateRightAscensionDegrees:(double)rightAscensionDegrees
                     approximateDeclinationDegrees:(double)declinationDegrees
           approximateHorizontalFieldOfViewDegrees:(double)fieldOfViewDegrees
                                    minimumMatches:(NSInteger)minimumMatches
                                             error:(NSError **)error {
    try {
        const PreparedImage prepared = prepareImage(imageURL);
        camerae_vision::plate_solving::ConstrainedPlateSolveRequest request;
        request.detectedStars = prepared.detection.stars;
        request.imageWidth = prepared.detection.imageWidth;
        request.imageHeight = prepared.detection.imageHeight;
        request.catalog = camerae_vision::plate_solving::deserializeCompactCatalog(
            catalogBytes(catalogURL)
        );
        request.approximateCenter = {
            rightAscensionDegrees,
            declinationDegrees
        };
        request.approximateHorizontalFieldOfViewDegrees = fieldOfViewDegrees;
        request.minimumMatches = static_cast<int>(minimumMatches);
        request.matchTolerancePixels = 16.0;
        const auto solution =
            camerae_vision::plate_solving::solveConstrained(request);
        if (solution.status ==
            camerae_vision::plate_solving::PlateSolvingStatus::InvalidInput) {
            assignError(error, 3, @"Invalid constrained plate-solving input.");
            return nil;
        }
        return makeResult(prepared.detection, &solution);
    } catch (const std::exception& exception) {
        assignError(
            error,
            3,
            [NSString stringWithUTF8String:exception.what()]
        );
        return nil;
    }
}

@end
