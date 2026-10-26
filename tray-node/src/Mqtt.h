#pragma once
// leaveguard/belongings/<device_id>/...
//   observation   out  관측 JSON          QoS 1
//   availability  out  online / offline   QoS 1, retain, LWT
//   health        out  상태 JSON          QoS 0
//   command       in   {"cmd":"rescan","request_id":"..."}  QoS 1, retain 하면 재접속마다 다시 실행된다
#include <unistd.h>
#include <atomic>
#include <cstdio>
#include <cstring>
#include <functional>
#include <string>
#include <mosquitto.h>

class MqttLink {
public:
    using CommandHandler = std::function<void(const std::string& payload)>;

    MqttLink(std::string host, int port, std::string clientId, std::string base, CommandHandler onCommand)
        : host(std::move(host)), port(port), clientId(std::move(clientId)), base(std::move(base)), onCommand(std::move(onCommand)) {}

    ~MqttLink() { stop(); }

    bool start() {
        mosquitto_lib_init();
        m = mosquitto_new(clientId.c_str(), true, this);
        if (!m) return false;
        mosquitto_connect_callback_set(m, [](mosquitto*, void* self, int rc) { static_cast<MqttLink*>(self)->connected_(rc); });
        mosquitto_disconnect_callback_set(m, [](mosquitto*, void* self, int) { static_cast<MqttLink*>(self)->up = false; });
        mosquitto_message_callback_set(m, [](mosquitto*, void* self, const mosquitto_message* msg) {
            auto* l = static_cast<MqttLink*>(self);
            if (msg->topic == l->topic("command") && l->onCommand)
                l->onCommand(std::string(static_cast<const char*>(msg->payload), msg->payloadlen));
        });
        mosquitto_reconnect_delay_set(m, 1, 10, true);
        std::string avail = topic("availability");
        mosquitto_will_set(m, avail.c_str(), 7, "offline", 1, true);
        // 첫 연결이 실패해도 loop 스레드가 다시 붙는다
        int rc = mosquitto_connect_async(m, host.c_str(), port, KEEPALIVE);
        if (rc != MOSQ_ERR_SUCCESS) std::fprintf(stderr, "[mqtt] %s:%d 첫 연결 실패: %s — 계속 다시 시도\n", host.c_str(), port, mosquitto_strerror(rc));
        return mosquitto_loop_start(m) == MOSQ_ERR_SUCCESS;
    }

    // 정상 종료에는 LWT 가 나가지 않으므로 offline 을 직접 보낸다
    void stop() {
        if (!m) return;
        if (up) {
            std::string avail = topic("availability");
            mosquitto_publish(m, nullptr, avail.c_str(), 7, "offline", 1, true);
            usleep(300000);
        }
        mosquitto_disconnect(m);
        mosquitto_loop_stop(m, false);
        mosquitto_destroy(m);
        m = nullptr;
        mosquitto_lib_cleanup();
    }

    bool connected() const { return up; }

    // 끊겨 있으면 버린다 (쌓아 두지 않음)
    bool publish(const std::string& kind, const std::string& payload, int qos, bool retain) {
        if (!m || !up) return false;
        std::string t = topic(kind);
        return mosquitto_publish(m, nullptr, t.c_str(), (int)payload.size(), payload.data(), qos, retain) == MOSQ_ERR_SUCCESS;
    }

    std::string topic(const std::string& kind) const { return base + "/" + kind; }

private:
    static constexpr int KEEPALIVE = 10;   // 끊긴 뒤 ~15초 안에 LWT

    void connected_(int rc) {
        if (rc != 0) {
            std::fprintf(stderr, "[mqtt] 연결 거부: %s\n", mosquitto_connack_string(rc));
            return;
        }
        up = true;
        std::string avail = topic("availability"), cmd = topic("command");
        mosquitto_publish(m, nullptr, avail.c_str(), 6, "online", 1, true);
        mosquitto_subscribe(m, nullptr, cmd.c_str(), 1);
        std::fprintf(stderr, "[mqtt] %s:%d 연결 · %s/…\n", host.c_str(), port, base.c_str());
    }

    std::string host;
    int port;
    std::string clientId, base;
    CommandHandler onCommand;
    mosquitto* m = nullptr;
    std::atomic<bool> up{false};
};
