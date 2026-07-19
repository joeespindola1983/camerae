cmake_minimum_required(VERSION 3.20)

project(camerae_vision LANGUAGES CXX)

include(CTest)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

find_package(OpenCV REQUIRED COMPONENTS calib3d core features2d imgcodecs imgproc video)

add_library(camerae_vision
    src/opencv/alignment.cpp
    src/opencv/alignment_quality.cpp
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
endif()
