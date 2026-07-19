cmake_minimum_required(VERSION 3.20)

project(camerae_processing LANGUAGES CXX)

include(CTest)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

find_package(OpenCV REQUIRED COMPONENTS calib3d core features2d imgcodecs imgproc photo video)

if(NOT TARGET camerae_vision)
    add_subdirectory(
        ${CMAKE_CURRENT_SOURCE_DIR}/../vision
        ${CMAKE_CURRENT_BINARY_DIR}/camerae_vision
    )
endif()

add_library(camerae_processing
    src/astro_processor.cpp
)

target_include_directories(camerae_processing
    PUBLIC
        ${CMAKE_CURRENT_SOURCE_DIR}/include
        ${OpenCV_INCLUDE_DIRS}
)

target_link_libraries(camerae_processing
    PUBLIC
        camerae_vision
        ${OpenCV_LIBS}
)

add_executable(camerae-astro-preview
    tools/astro_preview.cpp
)

target_link_libraries(camerae-astro-preview
    PRIVATE
        camerae_processing
)

if(BUILD_TESTING)
    add_executable(camerae_processing_tests
        tests/astro_processor_tests.cpp
    )

    target_link_libraries(camerae_processing_tests
        PRIVATE
            camerae_processing
    )

    add_test(NAME camerae_processing_tests COMMAND camerae_processing_tests)
endif()
