#include "camerae_vision/diagnostics.hpp"

#include <iostream>
#include <stdexcept>
#include <string>

namespace {

using namespace camerae_vision;

void require(bool condition, const std::string& message) {
    if (!condition) {
        throw std::runtime_error(message);
    }
}

void testSchemaVersionIsStable() {
    require(cameraeVisionDiagnosticsSchemaVersion == 1,
            "first public diagnostics schema should be version 1");
}

void testReasonCodeNamesAreStableAndPortable() {
    require(alignmentReasonCodeName(AlignmentReasonCode::StableGeometry) == "stableGeometry",
            "stable geometry code should have a stable wire name");
    require(alignmentReasonCodeName(AlignmentReasonCode::InsufficientOverlap) ==
                "insufficientOverlap",
            "overlap code should have a stable wire name");
    require(alignmentReasonCodeName(AlignmentReasonCode::PossibleParallaxOrMotion) ==
                "possibleParallaxOrMotion",
            "parallax code should have a stable wire name");
}

} // namespace

int main() {
    try {
        testSchemaVersionIsStable();
        testReasonCodeNamesAreStableAndPortable();
        std::cout << "camerae_diagnostics_tests passed\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "camerae_diagnostics_tests failed: " << error.what() << "\n";
        return 1;
    }
}
