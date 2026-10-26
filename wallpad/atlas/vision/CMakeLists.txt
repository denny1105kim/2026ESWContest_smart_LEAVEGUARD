# Executable and models go to bundle vision/, OpenCV modules missing on the board go to bundle lib/.
find_package(PkgConfig REQUIRED)
pkg_check_modules(OPENCV REQUIRED opencv4)

add_executable(leaveguard_vision src/main.cpp)
target_compile_features(leaveguard_vision PRIVATE cxx_std_17)
target_include_directories(leaveguard_vision PRIVATE src third_party ${OPENCV_INCLUDE_DIRS})
target_link_libraries(leaveguard_vision PRIVATE
    opencv_core opencv_imgproc opencv_objdetect opencv_dnn
    camera-client camera_shared_memory)

# RPATH instead of RUNPATH so indirect deps (objdetect -> dnn) are also found in bundle lib/.
target_link_options(leaveguard_vision PRIVATE -Wl,--disable-new-dtags)

install(TARGETS leaveguard_vision RUNTIME DESTINATION vision)

install(DIRECTORY
    "${LEAVEGUARD_MODELS_DIR}/face-detection"
    "${LEAVEGUARD_MODELS_DIR}/face-recognition"
    "${LEAVEGUARD_MODELS_DIR}/anti-spoofing"
    DESTINATION vision/models)

# The board only ships OpenCV core/imgproc; take the rest (plus protobuf, abseil) from the SDK.
set(SDK_LIB "${CMAKE_SYSROOT}/usr/lib")

# installed under the SONAME (.so.409) the loader looks for
foreach(module objdetect dnn calib3d features2d flann)
    install(FILES "${SDK_LIB}/libopencv_${module}.so.4.9.0"
        DESTINATION lib RENAME "libopencv_${module}.so.409")
endforeach()

file(GLOB PROTOBUF_ABSEIL_LIBS "${SDK_LIB}/libprotobuf.so.*" "${SDK_LIB}/libabsl_*.so.*")
install(FILES ${PROTOBUF_ABSEIL_LIBS} DESTINATION lib)
