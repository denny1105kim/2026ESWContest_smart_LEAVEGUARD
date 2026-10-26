# door-node

ESP32-CAM 현관 카메라. 평소에는 초당 3장, Pi5(월패드)가 얼굴을 감지하면 초당 12장으로 Pi5에 HTTP POST(REST)한다. 속도 전환 명령은 Pi5가 MQTT로 보낸다.

```
            ┌──────────────── 평소: 3fps ────────────────┐
ESP32-CAM ──POST /api/camera/frames (JPEG 640x480)──▶ Pi5 (얼굴 감지·인식)
    ▲                                                  │
    └──── MQTT leaveguard/esp32cam/cam1/face ──────────┘
          "detected" → 12fps로 전환, 판정 대기
          "known"    → 12fps로 10초 더, 그다음 3fps
          "unknown"  → 12fps로 30초 더, 그다음 3fps
```

## 상태

| 상태 | fps | 들어가는 조건 | 나오는 조건 |
|---|---|---|---|
| `idle` | 3 | 부팅 직후, 각 상태 시간이 끝났을 때, `idle` 명령 | `detected`·`known`·`unknown` 명령 |
| `detected` | 12 | idle일 때 `detected` | `known`/`unknown` 명령, 또는 15초 안에 판정이 안 오면 idle |
| `known` | 12 | `known` (어느 상태에서든) | 10초 뒤 idle |
| `unknown` | 12 | `unknown` (어느 상태에서든) | 30초 뒤 idle |

이미 `detected`·`known`·`unknown`일 때 온 `detected`는 무시한다. 시간·fps는 `.ino` 맨 위 값(`IDLE_FPS`, `ACTIVE_FPS`, `KNOWN_S`, `UNKNOWN_S`, `RESULT_TIMEOUT_S`)으로 바꾼다.

## 프레임 전송 (Pi5 서버가 받아야 하는 규격)

```
POST http://192.168.0.50:8000/api/camera/frames
Content-Type: image/jpeg          본문 = JPEG 그대로 (640x480, 장당 약 8~12KB)
X-Device-Id: cam1
X-Mode: idle | detected | known | unknown     그 프레임을 찍을 때의 상태
X-Frame: 0, 1, 2 ...              부팅 후 보낸 프레임 번호
```

- 프레임 1장 = 요청 1번. 같은 TCP 연결(keep-alive)을 계속 쓰므로 서버는 keep-alive를 지원하면 좋다.
- 서버는 2xx로 빨리 응답한다. 무거운 인식은 응답 뒤에 따로 처리해야 12fps가 유지된다.
- 실패한 프레임은 다시 보내지 않고 다음 프레임으로 넘어간다.
- 받는 서버: 월패드 앱 `wallpad/lib/device/doorcam/door_cam_server.dart` (`POST /api/camera/frames`, 포트 8000).

## MQTT (브로커 = Pi5 `192.168.0.50:1883`)

| 토픽 | 방향 | 값 | QoS | retain |
|---|---|---|---|---|
| `leaveguard/esp32cam/cam1/face` | Pi5 → 카메라 | `detected` / `known` / `unknown` / `idle` | 1 | X |
| `leaveguard/esp32cam/cam1/state` | 카메라 → Pi5 | 지금 상태 `idle` / `detected` / `known` / `unknown` | 0 | O |
| `leaveguard/esp32cam/cam1/availability` | 카메라 → Pi5 | `online` / `offline` (LWT, 약 15초 뒤) | 1 | O |
| `leaveguard/door/lock/set` | Pi5 → 카메라 | `UNLOCK` (등록된 사람이고 문을 열어도 될 때 Pi5가 보냄) | 1 | X |
| `leaveguard/door/lock/state` | 카메라 → Pi5 | `LOCKED` / `UNLOCKED` | 0 | O |

`face`·`door/lock/set`에 retain을 켜면 안 된다. 카메라가 재접속할 때마다 옛 명령이 다시 실행된다(문이 다시 열린다).

> **브로커 보안:** 지금 브로커는 아이디·비밀번호 없이 누구나 접속할 수 있다. 같은 Wi-Fi에 있는 누구든 `leaveguard/door/lock/set`에 `UNLOCK`을 보내면 문이 열린다. 시연이 아닌 실제 설치에서는 **브로커에 아이디와 비밀번호를 걸고**(Mosquitto `password_file` + `allow_anonymous false`), 가능하면 `door/lock/set`은 Pi5 계정만 쓸 수 있게 ACL을 건다. 그러면 ESP32-CAM 코드의 `mqtt.connect()`에도 아이디·비밀번호를 넣어야 한다(`secrets.h`에 두기).

테스트 (브로커에 접속되는 아무 PC에서):

```bash
mosquitto_sub -h 192.168.0.50 -t 'leaveguard/esp32cam/cam1/#' -v
mosquitto_pub -h 192.168.0.50 -t leaveguard/esp32cam/cam1/face -m detected
mosquitto_pub -h 192.168.0.50 -t leaveguard/esp32cam/cam1/face -m known
```

## 도어락 (아두이노 우노 + SG90, [doorlock_uno/doorlock_uno.ino](doorlock_uno/doorlock_uno.ino))

등록된 사람이 돌아오면 Pi5가 `leaveguard/door/lock/set`에 `UNLOCK`을 보낸다. ESP32-CAM은 GPIO13에 0.2초 HIGH 신호를 주고, 우노가 SG90을 열림 각도로 돌렸다가 5초 뒤 잠근다.

```
Pi5 ──MQTT door/lock/set "UNLOCK"──▶ ESP32-CAM ──GPIO13 0.2초 HIGH──▶ 우노 D2 ──▶ SG90 (D9) 열림 각도, 5초 뒤 잠금 각도
                                       └─ door/lock/state UNLOCKED → 5초 뒤 LOCKED
```

배선:

```
ESP32-CAM GPIO13 ── 우노 D2
ESP32-CAM GND    ── 우노 GND           (꼭 연결)
SG90 주황 ── 우노 D9,  빨강 ── 5V,  갈색 ── GND
```

- 신호는 ESP32 → 우노 한 방향만. ESP32 3.3V 출력을 우노는 HIGH로 읽는다. 반대로 우노 5V를 ESP32 핀에 넣으면 안 된다.
- SG90은 움직일 때 순간 전류가 커서, 우노 5V 핀이나 ESP32-CAM 전원을 같이 쓰면 리셋될 수 있다. 별도 5V 어댑터를 쓰고 GND를 묶는다. 전원선 사이에 470µF 콘덴서를 권장.
- 열림 시간은 ESP32-CAM `DOOR_OPEN_S`와 우노 `OPEN_MS`를 같게 맞춘다(기본 5초). 각도는 우노 `LOCK_ANGLE`·`UNLOCK_ANGLE`.
- 열고 닫는 속도는 우노 `SPEED_PERCENT`(SG90 최고 속도 대비 %, 기본 20 → 90°에 약 0.75초). 1°씩 나눠 돌린다. 부팅 때 잠금 위치로 갈 때만 한 번에 간다(위치를 모르니까).
  우노는 다 연 뒤부터 `OPEN_MS`를 세므로 실제로 다 잠기는 건 ESP32-CAM이 `LOCKED`를 보낸 뒤 약 1.5초 뒤다.
- 열려 있는 동안 다시 온 `UNLOCK`은 무시한다(닫히는 시간을 늘리지 않음).
- 우노 보드는 Arduino IDE에서 "Arduino Uno", 라이브러리는 기본 포함된 Servo.

테스트:

```bash
mosquitto_sub -h 192.168.0.50 -t 'leaveguard/door/lock/state' -v
mosquitto_pub -h 192.168.0.50 -t leaveguard/door/lock/set -m UNLOCK
```

## ESP32-CAM 자체 HTTP 서버 (포트 8000, 확인용)

| 주소 | 응답 |
|---|---|
| `GET http://<ESP32IP>:8000/status` | `{"id":"cam1","ip":"…","rssi":-52,"server":"…","mqtt":true,"mode":"known","mode_left_s":7,"target_fps":12,"fps":12.0,"frames":1234,"last_code":200,"door":"LOCKED","uptime_s":600}` |
| `GET http://<ESP32IP>:8000/capture` | 지금 찍은 JPEG (서버로는 안 보냄) |

`door`는 `LOCKED`/`UNLOCKED`. `fps`는 최근 2초 동안 실제로 보낸 장수다. `target_fps`보다 많이 낮으면 해상도(`FRAME_SIZE`)나 화질(`JPEG_QUALITY`)을 낮춘다.

## ESP32-CAM ([esp32cam/esp32cam.ino](esp32cam/esp32cam.ino))

Arduino IDE.

- 보드 **ESP32 Wrover Module**, Upload Speed **115200**, PSRAM **Enabled**. "AI Thinker ESP32-CAM" 보드는 Upload Speed 메뉴가 없고 460800에서 업로드가 끊긴다.
- 라이브러리 **PubSubClient** (Nick O'Leary)를 Library Manager에서 설치.
- Wi-Fi 정보는 `esp32cam/secrets.h`에 둔다. `secrets.h.example`을 `secrets.h`로 복사해서 `WIFI_SSID`, `WIFI_PASS`를 채운다. `secrets.h`는 `.gitignore`에 있어서 git에 올라가지 않는다.
- 파일 맨 위 `SERVER_URL`, `MQTT_HOST`, `DEVICE_ID`, `HTTP_PORT`, `FRAME_SIZE`, `JPEG_QUALITY`, fps·시간 값을 맞춘다.
- 시리얼(115200)에 상태가 바뀔 때마다 `mode -> known for 10 s` 같은 줄을, 전송이 실패하면 응답 코드를 찍는다.
- 명령줄로 올리기: `arduino-cli compile --fqbn esp32:esp32:esp32wrover:UploadSpeed=115200 esp32cam && arduino-cli upload -p /dev/ttyUSB0 --fqbn esp32:esp32:esp32wrover:UploadSpeed=115200 esp32cam`
- 전원은 5V 2A 이상. 약하면 촬영 중에 재부팅(brownout)된다.

`ACTIVE_FPS`가 12인 이유: VGA·화질 14에서 실제로 나오는 속도가 12~13.5fps다.
