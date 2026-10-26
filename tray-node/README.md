# 트레이 노드 (Raspberry Pi 4)

트레이 위 카메라(Camera Module 3)로 물건 박스를 찾고, 박스마다 특징 벡터를 뽑아 관측 메시지로 월패드(Pi5)에 보낸다.
물건이 무엇인지, 누구 것인지는 월패드가 판단한다. 노드는 등록 데이터를 갖지 않는다.

처리 순서 (매 프레임):

0. 판 네 모서리가 저장돼 있으면 그 사각형을 화면에 꽉 차게 편다 (`board.txt`)
1. 움직임 판단 (`Stillness`)
2. 판넬 가장자리 띠로 판넬 색을 재고 벗어난 영역을 후보 박스로 (`PanelExtractor`)
3. `settle_frames` 동안 멈춰 있으면: YOLOX-Nano 보조 탐지로 박스를 나누거나 더하고 (`ItemDetector`),
   박스별로 특징을 뽑아 (`Encoder`) 관측을 보낸다. 같은 자리·같은 그림의 박스는 이전 벡터를 다시 쓴다.

장면이 무효(`scene_quality.valid = false`)이거나 후보가 0개여도 "물건 없음"을 뜻하지 않는다.

## 빌드

Raspberry Pi OS (trixie, OpenCV 4.10). OpenCV 4.6 은 DINOv2 ONNX 를 읽지 못한다.

```bash
sudo apt install cmake g++ make libopencv-dev libmosquitto-dev rpicam-apps
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build -j4
```

| 실행 파일 | 내용 | 의존성 |
|---|---|---|
| `tray-detection` | 서비스 | OpenCV (core, imgproc, imgcodecs, dnn), libmosquitto, `rpicam-vid` |
| `tray-detection-offline` | 저장 사진·크롭으로 박스·특징 추출 | OpenCV |
| `tray-detection-live` | 화면을 보며 판넬 값 맞추기, 모델 시연 | OpenCV highgui 가 있을 때만 빌드 |

## 설치

```bash
sudo useradd -r -G video,render leaveguard   # 서비스 사용자 (없을 때만)
sudo install -D -m 755 build/tray-detection /opt/leaveguard/tray-detection/tray-detection
sudo install -D -m 644 deploy/tray-detection.json /etc/leaveguard/tray-detection.json
sudo install -D -m 644 -t /opt/leaveguard/models \
    ../models/tray/orbit_protonets_effb0_224.onnx \
    ../models/tray/dinov2_vits14_reg_168.onnx \
    ../models/tray/yolox_tray_items_new9_512.onnx
sudo install -m 644 deploy/leaveguard-tray-detection.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now leaveguard-tray-detection
journalctl -u leaveguard-tray-detection -f
```

카메라는 한 프로그램만 열 수 있으므로 `tray-detection-live` 를 쓸 때는 서비스를 먼저 멈춘다.

## 설정 (`/etc/leaveguard/tray-detection.json`)

| 키 | 내용 |
|---|---|
| `device_id` | 토픽과 관측의 장치 이름 |
| `encoder.preset`, `encoder.model` | 특징 모델 (`orbit_protonets_effb0_224` 또는 `dinov2_vits14_reg_168`) |
| `encoder2.preset`, `encoder2.model` | 선택. 있으면 두 모델 벡터를 각각 L2 정규화해 이어 붙인다 |
| `detector.model`, `input`, `score`, `nms`, `min_fill` | YOLOX 보조 탐지. `model` 이 없으면 쓰지 않는다 |
| `camera.width`, `height`, `fps`, `args` | `rpicam-vid` 설정. 폭은 128 배수, `args` 는 그대로 넘긴다 |
| `roi` 또는 `roi_polygon` | 판넬 영역 (원본 픽셀). 다각형이 있으면 그것을 쓴다 |
| `panel.*` | `PanelParams` 값 (`band`, `edge`, `lightSigma` 등) |
| `roi_version` | 설치 설정 이름, 관측에 그대로 실린다 |
| `settle_frames`, `refresh_sec`, `max_candidates` | 관측 조건, 갱신 주기, 박스 수 상한 (넓은 순) |
| `mqtt.host`, `port`, `health_sec` | 브로커. `host` 가 비면 MQTT 를 쓰지 않는다 |
| `http.bind`, `port` | HTTP 서버 |
| `out_dir`, `save_dir`, `save_max` | `latest.json` 위치, 안정 프레임 저장 위치와 최대 장수 |

## 판 맞추기 · 밝기 조절

시연 자리를 잡을 때, 카메라나 검은 판을 옮겼을 때 한 번 한다.

판 맞추기 (같은 Wi-Fi 의 브라우저로 `http://<트레이 IP>:8080`):

1. [세팅 모드 켜기] — 30fps 원본 영상으로 바뀌고 인식은 멈춘다 (10분 뒤 자동 해제)
2. 검은 판 네 모서리가 화면 안에 다 들어오게 카메라 · 판을 놓는다
3. [빨간 박스로 판 잡기] — 빨간 점 네 개를 판 모서리로 끈다 (왼위 → 오른위 → 오른아래 → 왼아래)
4. [판 저장] → [세팅 모드 끄기]. 모서리는 `out_dir/board.txt` 에 남고, 되돌릴 때는 [판 잡기 해제]
5. 미리보기 맨 위 줄이 `valid` 면 끝. 판을 바꾼 뒤에는 소지품을 다시 등록하는 것이 좋다

밝기 (`camera.args`, 바꾼 뒤 `sudo systemctl restart leaveguard-tray-detection`):

| 증상 | 조절 |
|---|---|
| 전체가 어둡다, 검은 물건이 판에 묻힌다 | `--shutter` 올리기 (10fps 에서 최대 약 90000) |
| 하얀 물건이 하얗게 날아간다 | `--shutter` 내리기 |
| 셔터를 더 올릴 수 없다 | `--gain` 올리기 (노이즈가 는다) |
| 밝은 것과 어두운 것이 같이 있다 | `--hdr sensor` 유지 |

미리보기 맨 위 줄의 `L` 이 평균 밝기(0~255)다. 15 아래 · 245 위면 `exposure` 로 관측을 멈춘다 (불을 끄면 그렇게 된다).
지금 설정은 `--shutter 55000 --gain 2.0 --hdr sensor` 다.

## MQTT

토픽 접두사 `leaveguard/belongings/<device_id>/`. 끊긴 동안의 관측은 쌓지 않고 버리며, 1~10초 간격으로 다시 연결한다.

| 토픽 | 방향 | 내용 | QoS · retain |
|---|---|---|---|
| `observation` | 노드 → 월패드 | 관측 JSON | 1 · 아니오 |
| `availability` | 노드 → 월패드 | `online` / `offline` (LWT) | 1 · 예 |
| `health` | 노드 → 월패드 | 상태 JSON, `health_sec` 마다, 카메라가 멈추면 바로 | 0 · 아니오 |
| `command` | 월패드 → 노드 | `{"cmd":"rescan","request_id":"..."}` 또는 `rescan` | 1 · retain 하지 않는다 |

`rescan` 을 받으면 요청 이후 찍힌 프레임으로 다시 관측하고, 응답 관측에 `request_id` 를 싣는다.

## HTTP (기본 `:8080`, 인증 없음, LAN 전용)

| 경로 | 내용 |
|---|---|
| `GET /` | 미리보기 + 상태 페이지 |
| `GET /health` | 상태 JSON |
| `GET /latest.json` | 마지막 관측 |
| `GET /preview.mjpeg`, `/preview.jpg` | 후보를 그린 영상 / 한 장 |
| `GET /raw.mjpeg` | 박스 없는 영상 (960 폭, 장마다 `X-Frame-Seq`) |
| `GET /snapshot.jpg[?frame_id=N]` | 원본 한 장 (`X-Frame-Seq`). 최근 관측 프레임 16장까지 |
| `GET /crop.jpg?frame_id=N&x=&y=&w=&h=` | 박스 하나 (여백 12%, 긴 변 320 이하) |
| `POST /encode?frame_id=N&x=&y=&w=&h=[&save=1][&rot=90\|180\|270]` | 박스 하나의 특징 JSON. `save=1` 이면 프레임과 박스를 `out_dir/redbox/` 에 남긴다. `rot` 은 돌려서 본 특징 (등록 때 돌린 모습도 저장) |
| `POST /rescan[?request_id=ID]` | MQTT `rescan` 과 같다 |
| `POST /setup?on=1\|0` | 세팅 모드: 30fps 원본 영상, 인식 멈춤, 10분 뒤 자동 해제 |
| `GET /board`, `POST /board?pts=x_y_x_y_x_y_x_y`, `POST /board?clear=1` | 판 네 모서리(왼위 · 오른위 · 오른아래 · 왼아래). 있으면 그 사각형을 화면에 꽉 차게 펴서 트레이로 본다 |

움직임이 멈춘 직후나 박스가 바뀐 뒤에는 세 번 더 약 1초마다 관측하고, 그 밖에는 `refresh_sec` 마다 관측한다.

## 관측 메시지 (schema 2)

| 필드 | 내용 |
|---|---|
| `schema_version` | 2 |
| `device_id`, `boot_id`, `sequence`, `observation_id` | `boot_id` 는 서비스가 시작할 때마다 새로 만든다. `observation_id` = `device_id/boot_id/sequence` |
| `request_id` | rescan 응답이면 그 ID, 아니면 `null` |
| `captured_at`, `capture_monotonic_ns`, `frame_age_ms_at_send` | 촬영 시각(UTC, 참고용), 노드 단조 시계, 보낼 때 프레임 나이 |
| `image_width`, `image_height`, `frame_id`, `roi_version` | `bbox` 좌표 기준, HTTP 요청에 쓰는 프레임 번호 |
| `embedding_space_id`, `embedding_dim`, `dtype`, `l2_normalized` | 특징 공간 ID (모델 해시·전처리 포함), 차원, `f32le`, 정규화 여부 |
| `processing_ms` | 관측 처리 시간 |
| `scene_quality` | `valid`, `reason`, `moving`, `band_inliers`, `light_mad`, `chroma_mad`, `plane_tilt`, `foreground`, `mean_light` |
| `candidates[]` | `id`, `bbox` [x, y, w, h], `contrast`, `fill`, `parts`, `source` (`panel` · `split` · `model`), `embedding` (base64 f32le 또는 `null`) |

`scene_quality.reason`: `roi_too_small`, `band_occluded`, `object_on_band`, `exposure`, `too_much_foreground`,
`candidate_too_large`, YOLOX 박스로 대신 관측한 경우 `rescued_by_model:<원래 이유>`, 빈 판으로 본 경우 `empty_by_model:object_on_band`.

## 개발 도구

```bash
# 크롭 특징만
build/tray-detection-offline --encoder orbit_protonets_effb0_224 --model M.onnx --crops crops/*.png > crops.jsonl

# 판넬 사진에서 박스 + 특징 (out/ 에 _boxes.jpg · _mask.png · _cand<i>.png)
build/tray-detection-offline --encoder orbit_protonets_effb0_224 --model M.onnx --roi x,y,w,h \
    --detector D.onnx --det-input 512 --out out/ panel/*.jpg > obs.jsonl

# 화면에서 맞추기 (키: r ROI · m 마스크 · s 저장 · q 끝), --model 을 주면 등록·비교 시연
build/tray-detection-live --roi x,y,w,h --save captures/ -- --autofocus-mode manual --lens-position 3
```

offline·live 는 판넬 값을 `--param 이름=값` 으로 바꿀 수 있다 (서비스는 설정의 `panel.*`).
