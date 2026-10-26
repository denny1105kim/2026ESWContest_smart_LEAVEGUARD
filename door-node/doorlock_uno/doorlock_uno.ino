// 현관 도어락 (Arduino Uno + SG90). ESP32-CAM 신호를 받으면 열었다가 OPEN_MS 뒤 잠근다.
// 라이브러리: Servo
//
// 배선
//   ESP32-CAM GPIO13 ── D2 (TRIGGER_PIN)
//   ESP32-CAM GND    ── GND
//   SG90 주황(신호)  ── D9 (SERVO_PIN)
//   SG90 빨강(+)     ── 5V
//   SG90 갈색(-)     ── GND
//
// ESP32-CAM 쪽: ../esp32cam/esp32cam.ino 의 DOOR_PIN, DOOR_OPEN_S(=OPEN_MS/1000과 같게)

#include <Servo.h>

const int TRIGGER_PIN = 2;          // ESP32-CAM GPIO13에서 오는 신호
const int SERVO_PIN   = 9;          // SG90 신호선

const int LOCK_ANGLE   = 65;        // 잠김 각도
const int UNLOCK_ANGLE = 155;       // 열림 각도
const unsigned long OPEN_MS     = 5000;   // 열려 있는 시간 (ESP32-CAM의 DOOR_OPEN_S와 같게)
const unsigned long TRIGGER_MS  = 50;     // 이 시간 이상 HIGH여야 진짜 신호로 본다 (잡음 무시)
const unsigned long MOVE_MS     = 600;    // 부팅 때 잠금 위치로 갈 때 기다리는 시간. 그 뒤엔 신호를 끊어 떨림·발열을 줄인다
const int SPEED_PERCENT = 20;             // 열고 닫는 속도 (SG90 최고 속도 대비 %). 100이면 한 번에 휙
const unsigned long SETTLE_MS   = 200;    // 다 돌고 나서 신호를 끊기 전 기다리는 시간

// SG90 최고 속도 약 0.1초/60° (4.8V) → 1°당 약 1.7ms. SPEED_PERCENT만큼 늦춰 1°씩 돌린다
const unsigned long FULL_US_PER_DEG = 1700;
const unsigned long STEP_US = FULL_US_PER_DEG * 100 / SPEED_PERCENT;

Servo servo;

bool          unlocked = false;
unsigned long unlockedAt = 0;
unsigned long highSince = 0;        // D2가 HIGH가 된 시각 (0이면 LOW)
bool          triggerUsed = false;  // 이번 HIGH 펄스로 이미 열었는지
int           currentAngle = LOCK_ANGLE;   // 마지막으로 보낸 각도

// 부팅 때: 지금 위치를 모르니 바로 보내고 MOVE_MS 기다렸다가 신호를 끊는다
void moveTo(int angle)
{
    servo.attach(SERVO_PIN);
    servo.write(angle);
    delay(MOVE_MS);
    servo.detach();
    currentAngle = angle;
}

// 열기·잠그기: 지금 각도에서 1°씩 STEP_US 간격으로 천천히 돌린 뒤 신호를 끊는다
void sweepTo(int angle)
{
    servo.attach(SERVO_PIN);
    int step = (angle > currentAngle) ? 1 : -1;
    for (int a = currentAngle; a != angle; a += step) {
        servo.write(a + step);
        delay(STEP_US / 1000);
        delayMicroseconds(STEP_US % 1000);
    }
    delay(SETTLE_MS);
    servo.detach();
    currentAngle = angle;
}

void setup()
{
    Serial.begin(9600);
    pinMode(TRIGGER_PIN, INPUT);
    pinMode(LED_BUILTIN, OUTPUT);

    moveTo(LOCK_ANGLE);                 // 켜지면 잠금 위치로
    Serial.println("doorlock ready (LOCKED)");
}

void loop()
{
    // 1) ESP32-CAM 신호: TRIGGER_MS 이상 HIGH면 한 번만 열기
    if (digitalRead(TRIGGER_PIN) == HIGH) {
        if (highSince == 0) highSince = millis();
        if (!triggerUsed && millis() - highSince >= TRIGGER_MS) {
            triggerUsed = true;
            if (!unlocked) {
                Serial.println("UNLOCK");
                sweepTo(UNLOCK_ANGLE);
                digitalWrite(LED_BUILTIN, HIGH);
                unlocked = true;
                unlockedAt = millis();
            }
        }
    } else {
        highSince = 0;
        triggerUsed = false;
    }

    // 2) OPEN_MS가 지나면 잠그기
    if (unlocked && millis() - unlockedAt >= OPEN_MS) {
        Serial.println("LOCK");
        sweepTo(LOCK_ANGLE);
        digitalWrite(LED_BUILTIN, LOW);
        unlocked = false;
    }
}
