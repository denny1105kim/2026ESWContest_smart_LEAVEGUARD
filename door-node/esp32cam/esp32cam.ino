// ESP32-CAM 현관 카메라
// 평소 IDLE_FPS, Pi5가 얼굴 감지를 알리면 ACTIVE_FPS로 프레임을 Pi5에 HTTP POST 한다.
// 판정 결과(known/unknown)를 받으면 KNOWN_S/UNKNOWN_S초 더 보낸 뒤 idle로 돌아간다.
// 토픽·HTTP 규격·배선은 ../README.md
//
// 보드: Arduino IDE "ESP32 Wrover Module" (Upload Speed 115200, PSRAM Enabled), 라이브러리 PubSubClient
// Wi-Fi 정보: secrets.h.example을 secrets.h로 복사해서 채운다.
// 도어락: DOOR_PIN(GPIO13) ── 우노 D2, GND ── 우노 GND (../doorlock_uno)

#include <WiFi.h>
#include <HTTPClient.h>
#include <WebServer.h>
#include <PubSubClient.h>
#include "esp_camera.h"
#include "secrets.h"   // WIFI_SSID, WIFI_PASS

const char* SERVER_URL  = "http://192.168.0.50:8000/api/camera/frames";   // 프레임 받는 Pi5 서버
const char* MQTT_HOST   = "192.168.0.50";    // 브로커 = Pi5
const int   MQTT_PORT   = 1883;
const char* DEVICE_ID   = "cam1";
const int   HTTP_PORT   = 8000;              // ESP32-CAM 자체 HTTP 서버 포트 (보내는 포트 아님)
const int   DOOR_PIN    = 13;                // 우노 D2로 가는 신호선 (GPIO12/0/4/16은 쓰면 안 됨)

#define FRAME_SIZE        FRAMESIZE_VGA   // 640x480
#define JPEG_QUALITY      14              // 0~63, 작을수록 고화질·큰 파일
#define IDLE_FPS          3               // 평소
#define ACTIVE_FPS        12              // 얼굴 감지 후 (VGA에서 12~13.5fps가 한계)
#define KNOWN_S           10              // 등록된 사람: 결과 받은 뒤 ACTIVE_FPS로 보내는 시간
#define UNKNOWN_S         30              // 모르는 사람: 결과 받은 뒤 ACTIVE_FPS로 보내는 시간
#define RESULT_TIMEOUT_S  15              // detected 후 이 시간 안에 판정이 안 오면 idle로
#define POST_TIMEOUT_MS   2000            // 프레임 하나 보낼 때 기다리는 최대 시간
#define DOOR_PULSE_MS     200             // 우노에 주는 신호 길이
#define DOOR_OPEN_S       5               // 열려 있는 시간 (우노 스케치의 OPEN_MS와 같게)

// ESP32-CAM 핀
#define PWDN_GPIO_NUM  32
#define RESET_GPIO_NUM -1
#define XCLK_GPIO_NUM   0
#define SIOD_GPIO_NUM  26
#define SIOC_GPIO_NUM  27
#define Y9_GPIO_NUM    35
#define Y8_GPIO_NUM    34
#define Y7_GPIO_NUM    39
#define Y6_GPIO_NUM    36
#define Y5_GPIO_NUM    21
#define Y4_GPIO_NUM    19
#define Y3_GPIO_NUM    18
#define Y2_GPIO_NUM     5
#define VSYNC_GPIO_NUM 25
#define HREF_GPIO_NUM  23
#define PCLK_GPIO_NUM  22

enum Mode { IDLE, DETECTED, KNOWN, UNKNOWN };
const char* MODE_NAME[] = { "idle", "detected", "known", "unknown" };

WebServer    web(HTTP_PORT);
HTTPClient   http;                // 같은 TCP 연결을 계속 쓴다 (keep-alive)
WiFiClient   mqttNet;
PubSubClient mqtt(mqttNet);

String topicFace, topicState, topicAvail;
const char* TOPIC_LOCK_SET   = "leaveguard/door/lock/set";
const char* TOPIC_LOCK_STATE = "leaveguard/door/lock/state";

Mode     mode = IDLE;
uint32_t modeUntil = 0;           // 이 시각(millis)이 되면 idle로 (idle일 때는 안 씀)
bool     modeChanged = true;      // state 토픽 다시 발행할지

uint32_t frameNo = 0;
uint32_t nextFrameAt = 0;
int      lastCode = 0;
uint32_t lastMqttTry = 0;

// 도어락 상태
bool     doorUnlocked = false;
uint32_t doorPulseEnd = 0;        // 이 시각에 신호선을 LOW로
uint32_t doorLockAt = 0;          // 이 시각에 LOCKED로 (우노가 다시 잠그는 시각)
bool     doorChanged = true;      // lock/state 다시 발행할지

// fps 측정 (최근 구간)
uint32_t fpsWindowStart = 0, fpsWindowFrames = 0;
float    fpsNow = 0;

bool initCamera()
{
    camera_config_t c = {};
    c.ledc_channel = LEDC_CHANNEL_0;
    c.ledc_timer   = LEDC_TIMER_0;
    c.pin_d0 = Y2_GPIO_NUM;  c.pin_d1 = Y3_GPIO_NUM;  c.pin_d2 = Y4_GPIO_NUM;  c.pin_d3 = Y5_GPIO_NUM;
    c.pin_d4 = Y6_GPIO_NUM;  c.pin_d5 = Y7_GPIO_NUM;  c.pin_d6 = Y8_GPIO_NUM;  c.pin_d7 = Y9_GPIO_NUM;
    c.pin_xclk = XCLK_GPIO_NUM;   c.pin_pclk = PCLK_GPIO_NUM;
    c.pin_vsync = VSYNC_GPIO_NUM; c.pin_href = HREF_GPIO_NUM;
    c.pin_sccb_sda = SIOD_GPIO_NUM; c.pin_sccb_scl = SIOC_GPIO_NUM;
    c.pin_pwdn = PWDN_GPIO_NUM;   c.pin_reset = RESET_GPIO_NUM;
    c.xclk_freq_hz = 20000000;
    c.pixel_format = PIXFORMAT_JPEG;
    c.frame_size   = FRAME_SIZE;
    c.jpeg_quality = JPEG_QUALITY;

    if (psramFound()) {
        c.fb_count    = 2;
        c.fb_location = CAMERA_FB_IN_PSRAM;
        c.grab_mode   = CAMERA_GRAB_LATEST;   // 보내는 동안 쌓인 옛 프레임 말고 최신 프레임
    } else {
        Serial.println("no PSRAM -> VGA 이하만 가능");
        c.fb_count    = 1;
        c.fb_location = CAMERA_FB_IN_DRAM;
        c.frame_size  = FRAMESIZE_VGA;
    }

    esp_err_t err = esp_camera_init(&c);
    if (err != ESP_OK) {
        Serial.printf("camera init failed: 0x%x\n", err);
        return false;
    }
    return true;
}

void connectWiFi()
{
    if (WiFi.status() == WL_CONNECTED) return;
    Serial.printf("WiFi connecting to %s", WIFI_SSID);
    WiFi.mode(WIFI_STA);
    WiFi.setSleep(false);                 // 절전 끄기 → 전송 지연 줄임 (12fps에 중요)
    WiFi.begin(WIFI_SSID, WIFI_PASS);
    for (int i = 0; i < 40 && WiFi.status() != WL_CONNECTED; i++) {   // 최대 20초
        delay(500);
        Serial.print(".");
    }
    Serial.println();
    if (WiFi.status() == WL_CONNECTED) {
        Serial.printf("WiFi OK, IP %s, RSSI %d\n", WiFi.localIP().toString().c_str(), WiFi.RSSI());
    } else {
        Serial.println("WiFi failed, retry later");
    }
}

void setMode(Mode m, uint32_t seconds)
{
    mode = m;
    modeUntil = millis() + seconds * 1000UL;
    modeChanged = true;
    nextFrameAt = millis();               // fps가 바뀌니 바로 다음 프레임부터 적용
    Serial.printf("mode -> %s%s\n", MODE_NAME[m], m == IDLE ? "" : (String(" for ") + seconds + " s").c_str());
}

// lock/set 토픽의 UNLOCK. mqtt.loop() 안에서 불린다
void unlockDoor()
{
    if (doorUnlocked) {                   // 이미 열려 있으면 무시 (닫히는 시간도 늘리지 않음)
        Serial.println("door already unlocked");
        return;
    }
    digitalWrite(DOOR_PIN, HIGH);
    doorPulseEnd = millis() + DOOR_PULSE_MS;
    doorLockAt = millis() + DOOR_OPEN_S * 1000UL;
    doorUnlocked = true;
    doorChanged = true;
    Serial.printf("door UNLOCK (%d s)\n", DOOR_OPEN_S);
}

void onMqttMessage(char* topic, byte* payload, unsigned int len)
{
    String msg;
    for (unsigned int i = 0; i < len; i++) msg += (char)payload[i];   // payload는 끝에 '\0'이 없음
    msg.trim();

    if (strcmp(topic, TOPIC_LOCK_SET) == 0) {
        if (msg == "UNLOCK") unlockDoor();
        else Serial.printf("unknown lock command '%s'\n", msg.c_str());
        return;
    }
    if (topicFace != topic) return;
    msg.toLowerCase();

    if (msg == "detected") {
        if (mode == IDLE) setMode(DETECTED, RESULT_TIMEOUT_S);       // 이미 판정 중·판정 후면 무시
    } else if (msg == "known") {
        setMode(KNOWN, KNOWN_S);
    } else if (msg == "unknown") {
        setMode(UNKNOWN, UNKNOWN_S);
    } else if (msg == "idle") {
        setMode(IDLE, 0);
    } else {
        Serial.printf("unknown face command '%s'\n", msg.c_str());
    }
}

void connectMqtt()
{
    if (mqtt.connected() || millis() - lastMqttTry < 2000) return;   // 2초마다 재시도
    lastMqttTry = millis();

    String clientId = String("esp32cam-") + DEVICE_ID;
    // LWT: 갑자기 끊기면 브로커가 offline을 대신 발행
    if (mqtt.connect(clientId.c_str(), nullptr, nullptr, topicAvail.c_str(), 1, true, "offline")) {
        Serial.println("MQTT connected");
        mqtt.publish(topicAvail.c_str(), "online", true);
        mqtt.subscribe(topicFace.c_str(), 1);
        mqtt.subscribe(TOPIC_LOCK_SET, 1);
        modeChanged = true;
        doorChanged = true;
    } else {
        Serial.printf("MQTT connect failed, state %d\n", mqtt.state());
    }
}

// 프레임 하나 찍어서 보냄
void sendFrame()
{
    camera_fb_t* fb = esp_camera_fb_get();
    if (!fb) {
        Serial.println("capture failed");
        return;
    }

    http.begin(SERVER_URL);               // setReuse(true)라 연결이 살아 있으면 그대로 다시 씀
    http.setTimeout(POST_TIMEOUT_MS);
    http.addHeader("Content-Type", "image/jpeg");
    http.addHeader("X-Device-Id", DEVICE_ID);
    http.addHeader("X-Mode", MODE_NAME[mode]);
    http.addHeader("X-Frame", String(frameNo));
    int code = http.POST(fb->buf, fb->len);
    if (code != lastCode && (code < 200 || code >= 300)) {
        Serial.printf("frame %u -> %d %s\n", frameNo, code, code < 0 ? HTTPClient::errorToString(code).c_str() : "");
    }
    lastCode = code;
    if (code < 200 || code >= 300) {
        http.end();                       // 연결을 버리고 다음 프레임에서 새로 연결
    } else {
        http.getString();                 // 응답을 다 읽어야 연결을 다시 쓸 수 있다
    }
    esp_camera_fb_return(fb);
    frameNo++;

    // 최근 2초 fps
    fpsWindowFrames++;
    uint32_t w = millis() - fpsWindowStart;
    if (w >= 2000) {
        fpsNow = fpsWindowFrames * 1000.0 / w;
        fpsWindowStart = millis();
        fpsWindowFrames = 0;
    }
}

// GET /status
void handleStatus()
{
    long left = (mode == IDLE) ? 0 : (long)(modeUntil - millis()) / 1000;
    String r = String("{\"id\":\"") + DEVICE_ID + "\",\"ip\":\"" + WiFi.localIP().toString() +
               "\",\"rssi\":" + WiFi.RSSI() + ",\"server\":\"" + SERVER_URL +
               "\",\"mqtt\":" + (mqtt.connected() ? "true" : "false") +
               ",\"mode\":\"" + MODE_NAME[mode] + "\",\"mode_left_s\":" + left +
               ",\"target_fps\":" + (mode == IDLE ? IDLE_FPS : ACTIVE_FPS) +
               ",\"fps\":" + String(fpsNow, 1) + ",\"frames\":" + frameNo +
               ",\"last_code\":" + lastCode + ",\"door\":\"" + (doorUnlocked ? "UNLOCKED" : "LOCKED") +
               "\",\"uptime_s\":" + millis() / 1000 + "}";
    web.send(200, "application/json", r);
}

// GET /capture : 지금 찍은 JPEG를 응답으로 돌려준다 (서버로는 안 보냄)
void handleCapture()
{
    camera_fb_t* fb = esp_camera_fb_get();
    if (!fb) {
        web.send(503, "text/plain", "capture failed");
        return;
    }
    web.sendHeader("Cache-Control", "no-store");
    web.setContentLength(fb->len);
    web.send(200, "image/jpeg", "");
    web.client().write(fb->buf, fb->len);
    esp_camera_fb_return(fb);
}

void setup()
{
    Serial.begin(115200);
    Serial.println("\nesp32cam boot");

    pinMode(DOOR_PIN, OUTPUT);
    digitalWrite(DOOR_PIN, LOW);
    String base = String("leaveguard/esp32cam/") + DEVICE_ID;
    topicFace  = base + "/face";
    topicState = base + "/state";
    topicAvail = base + "/availability";

    if (!initCamera()) {
        delay(3000);
        ESP.restart();
    }
    connectWiFi();

    http.setReuse(true);
    mqtt.setServer(MQTT_HOST, MQTT_PORT);
    mqtt.setCallback(onMqttMessage);
    mqtt.setKeepAlive(10);                // 끊김 감지 약 15초
    mqtt.setSocketTimeout(2);

    web.on("/status", HTTP_GET, handleStatus);
    web.on("/capture", HTTP_GET, handleCapture);
    web.begin();
    Serial.printf("%d fps idle / %d fps active -> POST %s, MQTT %s\n", IDLE_FPS, ACTIVE_FPS, SERVER_URL, MQTT_HOST);
}

// 도어락 신호선·상태 시간 처리 (Wi-Fi가 끊겨도 신호는 꼭 내린다)
void runDoor()
{
    if (doorPulseEnd && (int32_t)(millis() - doorPulseEnd) >= 0) {
        digitalWrite(DOOR_PIN, LOW);
        doorPulseEnd = 0;
    }
    if (doorUnlocked && (int32_t)(millis() - doorLockAt) >= 0) {
        doorUnlocked = false;
        doorChanged = true;
        Serial.println("door LOCKED");
    }
}

void loop()
{
    runDoor();
    connectWiFi();
    if (WiFi.status() != WL_CONNECTED) {
        delay(500);
        return;
    }

    connectMqtt();
    mqtt.loop();
    web.handleClient();

    // 정해진 시간이 지나면 idle로
    if (mode != IDLE && (int32_t)(millis() - modeUntil) >= 0) setMode(IDLE, 0);

    if (modeChanged && mqtt.connected()) {
        mqtt.publish(topicState.c_str(), MODE_NAME[mode], true);
        modeChanged = false;
    }
    if (doorChanged && mqtt.connected()) {
        mqtt.publish(TOPIC_LOCK_STATE, doorUnlocked ? "UNLOCKED" : "LOCKED", true);
        doorChanged = false;
    }

    // 지금 상태의 fps로 프레임 보내기
    if ((int32_t)(millis() - nextFrameAt) >= 0) {
        int fps = (mode == IDLE) ? IDLE_FPS : ACTIVE_FPS;
        nextFrameAt += 1000 / fps;
        if ((int32_t)(millis() - nextFrameAt) > 0) nextFrameAt = millis();   // 밀렸으면 따라잡지 말고 지금부터
        sendFrame();
    } else {
        delay(1);
    }
}
