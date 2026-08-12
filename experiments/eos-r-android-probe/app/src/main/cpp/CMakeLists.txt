cmake_minimum_required(VERSION 3.22.1)
project(camerae_gphoto2_bridge C)

set(NATIVE_LIB_DIR "${CMAKE_CURRENT_LIST_DIR}/../jniLibs/${ANDROID_ABI}")

function(import_native_library target file_name)
    add_library(${target} SHARED IMPORTED)
    set_target_properties(${target} PROPERTIES
        IMPORTED_LOCATION "${NATIVE_LIB_DIR}/${file_name}"
    )
endfunction()

import_native_library(gphoto2 libgphoto2.so)
import_native_library(gphoto2_port libgphoto2_port.so)
import_native_library(ltdl libltdl.so)

add_library(gphoto2_bridge SHARED gphoto2_bridge.c)
target_include_directories(gphoto2_bridge PRIVATE "${CMAKE_CURRENT_LIST_DIR}/include")
target_compile_options(gphoto2_bridge PRIVATE -Wall -Wextra -Werror)
target_link_libraries(gphoto2_bridge gphoto2 gphoto2_port ltdl log)
