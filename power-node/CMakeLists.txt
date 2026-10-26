cmake_minimum_required(VERSION 3.14)
project(com.atlas.app.powernode)

# Include GNUInstallDirs for standard installation directories
include(GNUInstallDirs)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Find required packages
find_package(sdbus-c++ 2.0 REQUIRED)
set(MOSQUITTO_DIR /app/mosquitto-aarch64)

# Source files
set(SOURCES
    src/main.cpp
)

# Executable
add_executable(${PROJECT_NAME} ${SOURCES})

# Include directories
target_include_directories(${PROJECT_NAME}
    PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/include
        /usr/local/include
        ${MOSQUITTO_DIR}/include
)

# Link libraries
target_link_libraries(${PROJECT_NAME}
    PRIVATE
        SDBusCpp::sdbus-c++
        systemd
        amclient
        alog
        fmt
        ${MOSQUITTO_DIR}/lib/libmosquitto_static.a
        pthread
)

# Install
set(APP_INSTALL_DIR ${CMAKE_INSTALL_PREFIX}/apps/${PROJECT_NAME})
install(TARGETS ${PROJECT_NAME} DESTINATION ${APP_INSTALL_DIR})
install(FILES ${CMAKE_CURRENT_SOURCE_DIR}/files/appinfo.json DESTINATION ${APP_INSTALL_DIR})
