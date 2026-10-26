# 공개 모델 다운로드 (models/ 폴더 구조 그대로)
# usage: python download_models.py <출력 폴더>   예) python tools/download_models.py models
#  - YuNet, SFace : OpenCV Zoo 에서 onnx 그대로
#  - MiniFASNet   : pth 원본 (export_minifasnet_onnx.py 로 onnx 변환 필요)
#  - YOLOX-Nano   : Megvii 공식 onnx 그대로
#  - DINOv2-S reg : 라이선스만 (모델은 export_dinov2_onnx.py 가 torch hub 에서 받아 변환)

import sys
import os
import urllib.request

out = sys.argv[1]
zoo = "https://github.com/opencv/opencv_zoo/raw/main/models"
sfas = "https://raw.githubusercontent.com/minivision-ai/Silent-Face-Anti-Spoofing/master"
yolox = "https://github.com/Megvii-BaseDetection/YOLOX"

files = {
    f"{zoo}/face_detection_yunet/face_detection_yunet_2023mar.onnx": "face-detection/face_detection_yunet_2023mar.onnx",
    f"{zoo}/face_detection_yunet/LICENSE": "LICENSES/YuNet.MIT",
    f"{zoo}/face_recognition_sface/face_recognition_sface_2021dec.onnx": "face-recognition/face_recognition_sface_2021dec.onnx",
    f"{zoo}/face_recognition_sface/LICENSE": "LICENSES/SFace.Apache-2.0",
    f"{sfas}/resources/anti_spoof_models/2.7_80x80_MiniFASNetV2.pth": "anti-spoofing/pth/2.7_80x80_MiniFASNetV2.pth",
    f"{sfas}/resources/anti_spoof_models/4_0_0_80x80_MiniFASNetV1SE.pth": "anti-spoofing/pth/4_0_0_80x80_MiniFASNetV1SE.pth",
    f"{sfas}/LICENSE": "LICENSES/MiniFASNet.Apache-2.0",
    f"{yolox}/releases/download/0.1.1rc0/yolox_nano.onnx": "object-detection/yolox_nano.onnx",
    f"{yolox}/raw/main/LICENSE": "LICENSES/YOLOX.Apache-2.0",
    "https://raw.githubusercontent.com/facebookresearch/dinov2/main/LICENSE": "LICENSES/DINOv2.Apache-2.0",
}

for url, name in files.items():
    path = os.path.join(out, name)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    urllib.request.urlretrieve(url, path)
    print("saved", name, os.path.getsize(path))
