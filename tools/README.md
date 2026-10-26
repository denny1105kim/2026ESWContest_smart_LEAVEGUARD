# tools

PC에서 돌리는 모델 변환·학습 스크립트. 보드에는 올라가지 않는다.

## 모델 받기·변환 (`tools/`)

| 스크립트 | 하는 일 |
|---|---|
| `download_models.py` | YuNet·SFace·MiniFASNet(pth)·YOLOX-Nano 와 라이선스 파일을 `models/` 구조로 받는다 |
| `export_minifasnet_onnx.py` | MiniFASNet pth → ONNX |
| `export_dinov2_onnx.py` | DINOv2-S reg (torch hub) → ONNX |
| `export_orbit_onnx.py` | ORBIT ProtoNets EfficientNet-B0 특징 추출기 → ONNX |

## 트레이 물건 탐지기 학습 (`tools/tray-training/`)

1클래스 `item` YOLOX-Nano(`models/tray/yolox_tray_items_new9_512.onnx`)를 만든 파이프라인이다.
경로는 모두 저장소 루트 기준이고, 데이터는 `research/tray_bench/` 아래에 쌓인다.

| 스크립트 | 하는 일 |
|---|---|
| `item_catalog.py` | 생성할 소지품 목록과 프롬프트 |
| `gen_items.py` | 생성 모델로 단색 바탕 소지품 사진 만들기 |
| `gen_cutouts.py` | 생성 사진을 BiRefNet 으로 오리고 나쁜 것 거르기 |
| `make_cutouts.py` | Open Images·Commons 박스에서 rembg 로 오리기 (첫 실험 재료) |
| `abo_cutouts.py` | ABO 상품 사진에서 소지품 오리기 |
| `oi_cutouts.py` | Open Images V7 분할 마스크로 실제 사진 속 물건 오리기 |
| `gen_backgrounds.py` | 빈 판·책상 바탕 생성 |
| `real_capture.py` | 실제 트레이 사진 받기(capture), 차이로 정답 박스 만들기(label) |
| `real_labels.py` | 사람이 잡은 실제 정답으로 학습·시험 세트 + 실제 물건 오리기 |
| `make_scenes.py` | 바탕 + 오린 물건으로 장면 합성 (정답 COCO) |
| `warp_oblique.py` | 위에서 본 장면을 비스듬한 카메라 화면으로 원근 변환 |
| `make_trainset.py` | 장면 폴더들을 학습 세트(train/val.json)로 묶기 |
| `train_yolox.py` | YOLOX-Nano 미세조정 |
| `export_yolox_onnx.py` | 체크포인트 → 보드용 ONNX (디코딩 포함) + OpenCV 확인 |
| `predict_yolox.py` | 시험 장면 박스 예측 |
| `eval_boxes.py` | 예측 박스를 정답과 비교 (놓침·합쳐짐·잘못 잡음) |
| `eval_yolox.py` | 체크포인트를 다른 세트의 val 로 mAP 평가 |
| `eval_embeddings.py` | ORBIT·DINOv2 물건 재식별 평가 (CORe50) |
| `catalog_embeddings.py` | 월패드 "이게 뭔지" 제안용 종류별 대표 벡터 만들기 |

준비: `git clone https://github.com/Megvii-BaseDetection/YOLOX vendor/YOLOX`,
`weights/yolox_nano.pth` (YOLOX 릴리스 0.1.1rc0). 필요한 패키지: torch, opencv-python, numpy, pillow,
diffusers, transformers, rembg, onnx, onnxruntime, onnxsim, pycocotools.

순서 (예시):

```bash
T=tools/tray-training
# 1. 재료: 생성 사진·오리기·바탕
python $T/gen_items.py lumina && python $T/gen_cutouts.py lumina
python $T/abo_cutouts.py
python $T/oi_cutouts.py
python $T/gen_backgrounds.py 400
# 2. 장면 (Pi4 넓은 화면 기준 ROI 1240x852, 30.7 px/cm)
python $T/make_scenes.py train 20000 --sources gen_lumina,abo,oi,real --out wide --frame 1240x852 --px-per-cm 30.7 \
    --gen-bg 0.3 --real-bg 0.3 --empty 0.06 --distract 0.6 --stack 0.35 --dark 0.25 --camera
python $T/warp_oblique.py scenes_train_wide scenes_train_obl 20000 <빈 판 사진.jpg>   # 비스듬한 카메라일 때
# 3. 학습 세트 → 학습 → ONNX
python $T/make_trainset.py trainset-tray research/tray_bench/scenes_train_wide research/tray_bench/scenes_train_obl
python $T/train_yolox.py 40 trainset-tray 512
python $T/export_yolox_onnx.py yolox_nano_trainset-tray 512
# 4. 보드 모델 자리로 복사
cp runs/yolox_nano_trainset-tray/yolox_nano_items_512.onnx models/tray/yolox_tray_items_new9_512.onnx
```

장 수와 비율은 예시다. 입력 크기(512)는 보드 설정 `detector.input` 과 같아야 한다.

## 데이터와 라이선스

학습 데이터(생성 이미지, 오린 그림, 집에서 찍은 트레이 사진)는 저장소에 넣지 않았다. 개인 사진이 섞여 있다.
스크립트가 쓰는 외부 자료:

- Lumina-Image-2.0 (`gen_items.py`, `gen_backgrounds.py`): Apache-2.0. `gen_items.py` 의 `qwen` 선택지(Qwen-Image)도 Apache-2.0
- Amazon Berkeley Objects (`abo_cutouts.py`): CC BY 4.0
- Open Images V7 (`oi_cutouts.py`, `make_cutouts.py`): 이미지 CC BY 2.0, 분할 마스크 CC BY 4.0. `make_cutouts.py` 의 Wikimedia Commons 사진은 파일마다 라이선스가 다르다
- CORe50 (`eval_embeddings.py`, 평가만): CC BY 4.0
- 오리기 모델: BiRefNet (MIT), rembg U2Net·IS-Net
