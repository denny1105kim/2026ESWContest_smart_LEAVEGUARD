# wallpad

Raspberry Pi 5 (LG Atlas OS) 월패드 앱. Flutter 화면과 카메라·얼굴 인식 프로그램(`atlas/vision`), MQTT 브로커(`atlas/broker`)가 한 IPK 로 묶인다.

## 구성

```text
wallpad/
├── lib/
│   ├── main.dart
│   ├── app/          앱 상태(app_state.dart + state/ 역할별 extension), 화면 전환, 보드 연결
│   ├── core/         상수·설정(config), SQLite(data), 디자인 토큰(theme)
│   ├── device/       카메라·vision, 현관 카메라 서버, 브로커·MQTT, 전력 노드·Shelly, 음성 메모, PIR, Wi-Fi(ConnMan)
│   ├── shared/       공통 위젯, 한글 조합, 시각 표기
│   └── features/     auth · onboarding · checklist · belongings · doorcam · settings · weather · calendar
├── assets/           얼굴 가이드 SVG, Pretendard 폰트(OFL), 물건 카탈로그
├── atlas/
│   ├── runner/       Flutter 실행기 (flutter-elinux 템플릿, BSD)
│   ├── vision/       카메라 공유메모리 · YuNet · SFace · MiniFASNet (C++, OpenCV)
│   ├── broker/       mosquitto 2.0.21 빌드 · 설정
│   └── meta/appinfo.json
├── system/           보드에 직접 넣는 D-Bus 정책 (PIR GPIO)
└── test/
```

모델은 저장소 루트 `models/` 에서 빌드 때 필요한 것만 번들에 복사된다.

## 빌드 · 설치

LG전자가 제공하는 개발 환경(저장소에 포함하지 않음)에서 빌드하면 화면과 `atlas/vision`, `atlas/broker` 가 한 IPK 로 묶이고, 그 IPK 를 월패드에 설치한다.

- 날씨·미세먼지 API 키와 캘린더 서버 주소는 보드의 `home/.config/leaveguard/device.json` 에 둔다 (저장소에 없음).
- 다시 설치하기 전에는 앱 데이터의 `leaveguard.db` 를 백업한다.
- PIR 을 쓰려면 `system/leaveguard-peripheral.conf` 를 보드의 D-Bus 정책 폴더에 넣는다.

## 보드에 따로 두는 것

음성 메모는 `/data/leaveguard-models` 의 프로그램을 실행한다. 직접 빌드해서 넣는다.

| 파일 | 출처 |
|---|---|
| `stt/whisper-server`, `stt/whisper-cli`, `stt/ggml-small-q8_0.bin` | whisper.cpp (MIT), Whisper small (MIT) — `whisper-quantize ggml-small.bin ggml-small-q8_0.bin q8_0` |
| `llama-server`, `exaone-4.0-1.2b-Q4_K_M.gguf` | llama.cpp (MIT), EXAONE 4.0 1.2B (EXAONE AI Model License) |

## 연결

| 상대 | 방식 |
|---|---|
| 트레이 노드 (Pi4) | MQTT `leaveguard/belongings/tray01/…`, HTTP `:8080` 미리보기 |
| 전력 노드 (Pi4) | MQTT `leaveguard/power/<가전>/state·set`, 노드가 없으면 Shelly HTTP 직접 |
| 현관 카메라 (ESP32-CAM) | HTTP `POST :8000/api/camera/frames`, MQTT `leaveguard/esp32cam/cam1/face` |
| 도어락 (Uno) | MQTT `leaveguard/door/lock/set` |
| PIR | GPIO17 |

브로커는 앱이 함께 띄운다 (`atlas/broker/mosquitto.conf`, 1883).
