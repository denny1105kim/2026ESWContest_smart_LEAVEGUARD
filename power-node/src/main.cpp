#include <iostream>
#include <thread>
#include <csignal>
#include <chrono>
#include <sdbus-c++/sdbus-c++.h>
#include <alog.hpp>
#include <amclient/AMClient.h>
#include <systemd/sd-event.h>
#include <mosquitto.h>
#include <fstream>
#include <string>
#include <mutex>
#include <cstring>

// 브로커는 Pi5 월패드 앱이 띄운다. 주소를 바꾸려면 BROKER_CONFIG 에 "broker_host=<IP>" 한 줄
#define BROKER_HOST_DEFAULT "192.168.0.50"
#define BROKER_CONFIG "/data/leaveguard/powernode.conf"
#define BROKER_PORT 1883

#define SET_TOPIC_ALL   "leaveguard/power/+/set"        // 월패드 → 라파4전력노드 : ON / OFF (모든 가전 구독용)
#define SENSOR_TOPIC_ALL "shelly/+/sensor"              // Shelly 스크립트 → 라파4전력노드 : 전류값 (1초마다, shelly/sensor.js)
#define AVAIL_TOPIC "leaveguard/power/node/availability"   // 전력노드 생존 : online / offline

#define STALE_SEC 10   // 이 시간 동안 전류값이 없으면 UNKNOWN

// 모든 플러그 공통 판단 기준 (대기전력 0인 가전 전제)
#define ON_THRESHOLD 0.08   // 이 전류(A) 이상이면 사용 중 (220V에서 약 18W)
#define ON_CONFIRM   3      // IN_USE 확정에 필요한 연속 횟수 (1초 주기 → 초)
#define OFF_CONFIRM  10     // IDLE 확정에 필요한 연속 횟수

#define APP_ID "com.atlas.app.powernode"

// 가전 하나 = Shelly 플러그 하나
struct Device {
    const char* sensorTopic;   // Shelly → 전력노드 : 전류(A)
    const char* stateTopic;    // 전력노드 → 월패드 : UNKNOWN / IDLE / IN_USE
    const char* setTopic;      // 월패드 → 전력노드 : ON / OFF
    const char* plugCmdTopic;  // 전력노드 → Shelly : on / off
    // 공통 기준과 다르게 판단해야 하는 가전만 아래 값을 지정
    double onThreshold = ON_THRESHOLD;
    int onConfirm = ON_CONFIRM;
    int offConfirm = OFF_CONFIRM;

    std::string state = "UNKNOWN";
    std::string candidate = "";
    int count = 0;
    std::chrono::steady_clock::time_point lastSample;  // 마지막으로 전류값을 받은 시각
    bool hasSample = false;                            // 한 번이라도 받은 적 있는지
};

Device g_devices[] = {
    // 고데기
    { "shelly/iron/sensor",  "leaveguard/power/iron/state",  "leaveguard/power/iron/set",
      "shellyplugmg3-70af09f8bbb4/command/switch:0" },
    // 드라이기
    { "shelly/dryer/sensor", "leaveguard/power/dryer/state", "leaveguard/power/dryer/set",
      "shellyplugmg3-083af2d0c7a8/command/switch:0" },
};

std::mutex g_mutex;   // 두 스레드가 g_devices 상태를 같이 쓰니까 잠금용

void publishState(struct mosquitto* mosq, const Device& d)
{
    mosquitto_publish(mosq, NULL, d.stateTopic, d.state.size(), d.state.c_str(), 1, true);
}

// signal handler to exit the program
volatile sig_atomic_t g_stop_requested = 0;
void signalHandler(int signal) {
    alog::logInfo("APP_SIGNAL_RECEIVED", "Received signal: {}", signal);
    g_stop_requested = 1;
}

// 브로커 주소: 설정 파일의 broker_host=, 없으면 기본값
static std::string brokerHost()
{
    std::ifstream file(BROKER_CONFIG);
    std::string line;
    const std::string key = "broker_host=";
    while (std::getline(file, line)) {
        if (line.compare(0, key.size(), key) != 0) continue;
        std::string value = line.substr(key.size());
        value.erase(value.find_last_not_of(" \t\r") + 1);
        if (!value.empty()) return value;
    }
    return BROKER_HOST_DEFAULT;
}

// 브로커 접속(재접속 포함)될 때마다 불림 → 여기서 구독해야 재접속 후에도 구독이 유지됨
void onConnect(struct mosquitto* mosq, void* obj, int rc)
{
    if (rc != 0) {
        alog::logError("MQTT", "connect failed: {}", mosquitto_connack_string(rc));
        return;
    }
    alog::logInfo("MQTT", "connected");
    mosquitto_publish(mosq, NULL, AVAIL_TOPIC, strlen("online"), "online", 1, true);
    mosquitto_subscribe(mosq, NULL, SENSOR_TOPIC_ALL, 0);
    mosquitto_subscribe(mosq, NULL, SET_TOPIC_ALL, 1);
}

// 구독한 토픽에 메시지가 오면 불림
void onMessage(struct mosquitto* mosq, void* obj, const struct mosquitto_message* msg)
{
    std::string payload((const char*)msg->payload, msg->payloadlen);

    std::string topic = msg->topic;

    for (Device& d : g_devices) {
        // ---- 월패드 명령 처리 ----
        if (topic == d.setTopic) {
            if (payload != "ON" && payload != "OFF") {
                alog::logWarn("POWER", "unknown command on {}: '{}'", topic, payload);
                return;
            }
            const char* cmd = (payload == "ON") ? "on" : "off";   // Shelly는 소문자
            alog::logInfo("POWER", "{} {} -> {} {}", topic, payload, d.plugCmdTopic, cmd);
            mosquitto_publish(mosq, NULL, d.plugCmdTopic, strlen(cmd), cmd, 1, false);
            return;
        }

        if (topic != d.sensorTopic) {
            continue;
        }

        // ---- 전류값 처리 ----
        double amps;
        try {
            amps = std::stod(payload);
        } catch (const std::exception& e) {
            alog::logWarn("POWER", "bad payload on {}: '{}'", topic, payload);
            return;
        }

        std::lock_guard<std::mutex> lock(g_mutex);   // 여기서부터 함수 끝까지 잠금
        d.lastSample = std::chrono::steady_clock::now();
        d.hasSample = true;

        // 이번 값만 보고 판단
        std::string now = (amps >= d.onThreshold) ? "IN_USE" : "IDLE";

        // 같은 판단이 연속으로 나오는지 세기
        if (now == d.candidate) {
            d.count++;
        } else {
            d.candidate = now;
            d.count = 1;
        }

        int need = (now == "IN_USE") ? d.onConfirm : d.offConfirm;
        alog::logInfo("POWER", "{} current = {} A -> {} ({}/{})", d.stateTopic, amps, now, d.count, need);

        // 필요한 횟수만큼 연속으로 같고, 지금 상태와 다르면 → 상태 변경 + 발행
        if (d.count >= need && d.candidate != d.state) {
            d.state = d.candidate;
            alog::logInfo("POWER", "{} changed -> {}", d.stateTopic, d.state);
            publishState(mosq, d);
        }
        return;
    }
}

int main()
{
    try {
        // Create a connection to the system bus without service name
        // (client does not need service name basically)
        std::shared_ptr<sdbus::IConnection> connection = sdbus::createSystemBusConnection();

        // Create app-manager client object to register and get events
        AMClient client(APP_ID);

        client.registerRestartEventCallback([](const std::vector<std::string>& params) {
            try {
                alog::logInfo("EVT_RESTART", "Restart event callback executing with params:");
                for (size_t i = 0; i < params.size(); i++) {
                    alog::logInfo("EVT_RESTART", "  arg[{}]: {}", i, params[i]);
                }
                alog::logInfo("EVT_RESTART", "Restart event handling completed");
            } catch (const std::exception& e) {
                alog::logError("EVT_RESTART", "Exception in restart callback: {}", e.what());
            }
        });

        client.registerPauseEventCallback([](const std::vector<std::string>& params) {
            try {
                alog::logInfo("EVT_PAUSE", "Pause event callback executing with params:");
                for (size_t i = 0; i < params.size(); i++) {
                    alog::logInfo("EVT_PAUSE", "  arg[{}]: {}", i, params[i]);
                }
                alog::logInfo("EVT_PAUSE", "Pause event handling completed");
            } catch (const std::exception& e) {
                alog::logError("EVT_PAUSE", "Exception in pause callback: {}", e.what());
            }
        });

        alog::logInfo("EVT_REGISTERED", "Event callbacks registered");
        client.initializeCallbacks();

        alog::logInfo("APP", "powernode started");

        // Use sd_event for the event loop
        __attribute__((cleanup(sd_event_unrefp))) sd_event *event = NULL;

        sd_event_default(&event);

        mosquitto_lib_init();
        struct mosquitto* mosq = mosquitto_new("powernode", true, NULL);
        if (!mosq) {
            alog::logError("MQTT", "mosquitto_new failed");
            return 1;
        }
        mosquitto_connect_callback_set(mosq, onConnect);
        mosquitto_message_callback_set(mosq, onMessage);
        mosquitto_reconnect_delay_set(mosq, 1, 10, true);   // 끊기면 1초~10초 간격으로 재접속
        mosquitto_will_set(mosq, AVAIL_TOPIC, strlen("offline"), "offline", 1, true);

        const std::string host = brokerHost();
        alog::logInfo("MQTT", "broker {}:{}", host, BROKER_PORT);
        int rc = mosquitto_connect(mosq, host.c_str(), BROKER_PORT, 10);
        if (rc != MOSQ_ERR_SUCCESS) {
            // 실패해도 아래 loop_start 가 계속 재접속을 시도함
            alog::logWarn("MQTT", "first connect failed: {}", mosquitto_strerror(rc));
        }
        mosquitto_loop_start(mosq);   // 별도 스레드에서 수신/송신/재접속 처리 시작

        // IMPORTANT: attach the D-Bus connection to event loop to receive signals and async calls
        connection->attachSdEventLoop(event);

        // Set up signal handlers without SA_RESTART to ensure signals interrupt epoll
        struct sigaction sa = {};
        sa.sa_handler = signalHandler;
        sa.sa_flags = 0;  // No SA_RESTART
        sigemptyset(&sa.sa_mask);

        if (sigaction(SIGINT, &sa, nullptr) < 0 || sigaction(SIGTERM, &sa, nullptr) < 0) {
            alog::logWarn("SIGNAL_SETUP", "Failed to set up signal handlers. Signals may not be handled correctly.");
        }

        // Run event loop with signal check
        while (!g_stop_requested) {
            int r = sd_event_run(event, 100000); // 100ms timeout for responsive signal handling
            if (r < 0 && r != -EINTR) {
                alog::logError("APP_EVENTLOOP", "Failed to run event loop: {}", strerror(-r));
                return 1;
            }

            std::lock_guard<std::mutex> lock(g_mutex);
            for (Device& d : g_devices) {
                if (!d.hasSample || d.state == "UNKNOWN") {
                    continue;
                }
                auto elapsed = std::chrono::steady_clock::now() - d.lastSample;
                if (elapsed > std::chrono::seconds(STALE_SEC)) {
                    d.state = "UNKNOWN";
                    d.candidate = "";
                    d.count = 0;
                    alog::logWarn("POWER", "{} no data for {} s -> UNKNOWN", d.stateTopic, STALE_SEC);
                    publishState(mosq, d);
                }
            }
        }

        mosquitto_publish(mosq, NULL, AVAIL_TOPIC, strlen("offline"), "offline", 1, true);
        std::this_thread::sleep_for(std::chrono::milliseconds(500));
        mosquitto_disconnect(mosq);
        mosquitto_loop_stop(mosq, true);   // false면 재접속 대기(최대 10초) 중에 systemd(5초)가 강제 종료함
        mosquitto_destroy(mosq);
        mosquitto_lib_cleanup();
    }
    catch (const std::exception& e) {
        alog::logError("APP_EXCEPTION", "Exception: {}", e.what());
        return 1;
    }

    alog::logInfo("APP_EXIT", "Application stopped. Exiting...");
    return 0;
}
