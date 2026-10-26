# Atlas 에는 브로커가 없고 /etc 가 읽기 전용이라, 월패드 앱 번들에 mosquitto 를 넣어 앱이 직접 띄운다
include(FetchContent)

set(MOSQUITTO_TARBALL "https://mosquitto.org/files/source/mosquitto-2.0.21.tar.gz" CACHE STRING "mosquitto source tarball (URL or file)")

set(WITH_BROKER   ON  CACHE BOOL "" FORCE)
set(WITH_CLIENTS  OFF CACHE BOOL "" FORCE)
set(WITH_APPS     OFF CACHE BOOL "" FORCE)
set(WITH_PLUGINS  OFF CACHE BOOL "" FORCE)
set(DOCUMENTATION OFF CACHE BOOL "" FORCE)
set(WITH_CJSON    OFF CACHE BOOL "" FORCE)
set(WITH_LIB_CPP  OFF CACHE BOOL "" FORCE)
# 2.0.21 은 TLS 를 끄면 브로커 소스가 빌드되지 않는다
set(WITH_TLS      ON  CACHE BOOL "" FORCE)

FetchContent_Declare(mosquitto
    URL "${MOSQUITTO_TARBALL}"
    URL_HASH SHA256=7ad5e84caeb8d2bb6ed0c04614b2a7042def961af82d87f688ba33db857b899d
    EXCLUDE_FROM_ALL)
FetchContent_MakeAvailable(mosquitto)

add_custom_target(leaveguard_broker ALL DEPENDS mosquitto)
install(PROGRAMS "$<TARGET_FILE:mosquitto>" DESTINATION broker)
install(FILES "${CMAKE_CURRENT_SOURCE_DIR}/mosquitto.conf" DESTINATION broker)
