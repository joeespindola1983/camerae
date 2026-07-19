cmake_minimum_required(VERSION 3.20)

project(camerae_vision LANGUAGES CXX)

include(CTest)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

find_package(OpenCV REQUIRED COMPONENTS calib3d core features2d imgcodecs imgproc video)

add_library(camerae_vision
    src/automatic_alignment.cpp
    src/opencv/alignment.cpp
    src/opencv/alignment_quality.cpp
    src/capture_support.cpp
)

target_include_directories(camerae_vision
    PUBLIC
        ${CMAKE_CURRENT_SOURCE_DIR}/include
        ${OpenCV_INCLUDE_DIRS}
)

target_link_libraries(camerae_vision
    PUBLIC
        ${OpenCV_LIBS}
)

add_executable(camerae-alignment-preview
    tools/alignment_lab.cpp
)

target_link_libraries(camerae-alignment-preview
    PRIVATE
        camerae_vision
)

add_library(camerae_capture_quality_simulator_support
    tools/capture_quality_simulator_support.cpp
)

target_include_directories(camerae_capture_quality_simulator_support
    PUBLIC
        ${CMAKE_CURRENT_SOURCE_DIR}/tools
)

target_link_libraries(camerae_capture_quality_simulator_support
    PUBLIC
        camerae_vision
)

add_executable(camerae-capture-quality-simulator
    tools/capture_quality_simulator.cpp
)

target_link_libraries(camerae-capture-quality-simulator
    PRIVATE
        camerae_capture_quality_simulator_support
)

if(BUILD_TESTING)
    add_executable(camerae_vision_tests
        tests/alignment_tests.cpp
    )

    target_link_libraries(camerae_vision_tests
        PRIVATE
            camerae_vision
    )

    add_test(NAME camerae_vision_tests COMMAND camerae_vision_tests)

    add_executable(camerae_alignment_quality_tests
        tests/alignment_quality_tests.cpp
    )

    target_link_libraries(camerae_alignment_quality_tests
        PRIVATE
            camerae_vision
    )

    add_test(NAME camerae_alignment_quality_tests COMMAND camerae_alignment_quality_tests)

    add_executable(camerae_capture_quality_simulator_tests
        tests/capture_quality_simulator_tests.cpp
    )

    target_link_libraries(camerae_capture_quality_simulator_tests
        PRIVATE
            camerae_capture_quality_simulator_support
    )

    add_test(
        NAME camerae_capture_quality_simulator_tests
        COMMAND camerae_capture_quality_simulator_tests
    )

    add_executable(camerae_capture_support_tests
        tests/capture_support_tests.cpp
    )

    target_link_libraries(camerae_capture_support_tests
        PRIVATE
            camerae_vision
    )

    add_test(NAME camerae_capture_support_tests COMMAND camerae_capture_support_tests)

    add_executable(camerae_automatic_alignment_tests
        tests/automatic_alignment_tests.cpp
    )

    target_link_libraries(camerae_automatic_alignment_tests
        PRIVATE
            camerae_vision
    )

    add_test(NAME camerae_automatic_alignment_tests COMMAND camerae_automatic_alignment_tests)
endif()
