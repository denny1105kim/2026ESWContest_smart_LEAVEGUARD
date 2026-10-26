#   tray-detection          service (camera, boxes, features, HTTP, MQTT)
#   tray-detection-offline  boxes/features from saved images
#   tray-detection-live     on-screen tuning tool, built only if highgui is available
cmake_minimum_required(VERSION 3.16)
project(leaveguard_tray_detection CXX)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE Release)
endif()

find_package(OpenCV REQUIRED COMPONENTS core imgproc imgcodecs dnn)
find_package(Threads REQUIRED)

add_executable(tray-detection-offline src/offline.cpp)
target_include_directories(tray-detection-offline PRIVATE src)
target_link_libraries(tray-detection-offline PRIVATE ${OpenCV_LIBS})

find_package(PkgConfig REQUIRED)
pkg_check_modules(MOSQUITTO REQUIRED IMPORTED_TARGET libmosquitto)
add_executable(tray-detection src/node.cpp)
target_include_directories(tray-detection PRIVATE src)
target_link_libraries(tray-detection PRIVATE ${OpenCV_LIBS} PkgConfig::MOSQUITTO Threads::Threads)

if(TARGET opencv_highgui)
  add_executable(tray-detection-live src/live.cpp)
  target_include_directories(tray-detection-live PRIVATE src)
  target_link_libraries(tray-detection-live PRIVATE ${OpenCV_LIBS} opencv_highgui Threads::Threads)
endif()
