# power-node

LeaveGuard 전력 노드 앱. LG Atlas OS 가 올라간 Raspberry Pi 4 에서 백그라운드 앱으로 동작한다.

- 전류값을 받아 가전 사용 여부(`IDLE` / `IN_USE`)를 판단해서 월패드(Pi5)로 보낸다.
- 월패드가 보낸 켜기/끄기 명령을 릴레이 명령으로 바꿔서 보낸다.

| 가전 | Shelly ID | 스크립트 `TOPIC` |
|---|---|---|
| 고데기 (`iron`) | `shellyplugmg3-70af09f8bbb4` | `shelly/iron/sensor` |
| 드라이기 (`dryer`) | `shellyplugmg3-083af2d0c7a8` | `shelly/dryer/sensor` |

## Shelly 준비

플러그마다 한다.

1. 웹 UI(`http://<플러그IP>`) → Settings → MQTT: "Enable MQTT" 켜기, Server를 Pi5 브로커(`<Pi5IP>:1883`)로, "Enable MQTT Control" 켜기, 저장 후 재부팅.
2. Scripts → 새 스크립트에 [shelly/sensor.js](shelly/sensor.js) 붙여넣고 `TOPIC`을 위 표대로 바꾸기 → 저장 → Run, "Run on startup" 켜기.
3. 확인: `mosquitto_sub -h <Pi5IP> -t 'shelly/+/sensor' -v` 에 1초마다 숫자가 오면 된다.

플러그를 바꾸면 `main.cpp`의 `g_devices`에 있는 기기 ID(`shellyplugmg3-…`)도 바꿔야 한다.

- 토픽 규약: [docs/mqtt-topics.md](docs/mqtt-topics.md)

## 판단 규칙

모든 플러그가 같은 기준으로 판단한다(대기전력이 0인 가전 전제). 값은 `main.cpp` 맨 위 `#define`에 있고, 전류값이 1초마다 오니까 횟수 = 초.

| 항목 | 값 | `main.cpp` |
|---|---|---|
| 사용 중 기준 | 0.08A 이상 (220V에서 약 18W) | `ON_THRESHOLD` |
| `IN_USE` 확정 | 3번 연속 | `ON_CONFIRM` |
| `IDLE` 확정 | 10번 연속 | `OFF_CONFIRM` |
| 데이터 끊김 | 10초 동안 전류값이 없으면 `UNKNOWN` (플러그 꺼짐·Wi-Fi 끊김·스크립트 중지) | `STALE_SEC` |

다르게 판단해야 하는 가전이 생기면 `g_devices`의 그 항목에만 `onThreshold`·`onConfirm`·`offConfirm`을 지정한다.

## 빌드·실행

LG전자가 제공하는 개발 환경에서 빌드해 기기에 설치한다. MQTT 는 libmosquitto(Eclipse Mosquitto 2.0.21)를 같은 환경에서 크로스 빌드해 링크한다.
