"""학습한 YOLOX-Nano 를 보드용 ONNX 로 내보내고 OpenCV 결과를 PyTorch 와 맞춰 본다.
격자 디코딩을 그래프에 넣어 보드는 임계값과 NMS 만 한다.

usage: python tools/tray-training/export_yolox_onnx.py [runs 아래 실행 폴더] [입력 크기 416]
"""
import json
import sys
from pathlib import Path

import cv2
import numpy as np
import torch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "vendor" / "YOLOX"))
from yolox.models import YOLOX, YOLOPAFPN, YOLOXHead      # noqa: E402

RUN = ROOT / "runs" / (sys.argv[1] if len(sys.argv) > 1 else "yolox_nano_trainset")
CKPT = RUN / "best.pth"
SIZE = int(sys.argv[2]) if len(sys.argv) > 2 else 416
OUT = RUN / ("yolox_nano_items.onnx" if SIZE == 416 else f"yolox_nano_items_{SIZE}.onnx")
INPUT = (SIZE, SIZE)


def main():
    ckpt = torch.load(CKPT, map_location="cpu", weights_only=False)
    categories = ckpt["categories"]
    print(f"분류 {len(categories)}개, 학습 mAP50-95 {ckpt['mAP']:.3f} (에폭 {ckpt['epoch'] + 1})")

    backbone = YOLOPAFPN(0.33, 0.25, in_channels=[256, 512, 1024], act="silu", depthwise=True)
    head = YOLOXHead(len(categories), 0.25, in_channels=[256, 512, 1024], act="silu", depthwise=True)
    model = YOLOX(backbone, head)
    for m in model.modules():                  # train_yolox.build_model 과 같은 BN 값 (빠지면 박스가 엉망)
        if isinstance(m, torch.nn.BatchNorm2d):
            m.eps, m.momentum = 1e-3, 0.03
    model.load_state_dict(ckpt["model"])
    model.eval()
    model.head.decode_in_inference = True      # 픽셀 좌표로 바로 내보낸다

    dummy = torch.randn(1, 3, *INPUT)
    torch.onnx.export(model, dummy, str(OUT), input_names=["images"], output_names=["output"],
                      opset_version=12, dynamo=False)

    try:
        import onnx
        from onnxsim import simplify
        simplified, ok = simplify(onnx.load(str(OUT)))
        if ok:
            onnx.save(simplified, str(OUT))
            print("그래프 단순화 완료")
    except Exception as e:
        print(f"단순화 건너뜀: {e}")

    # PyTorch 결과와 맞춰 본다
    with torch.no_grad():
        expected = model(dummy).numpy()
    net = cv2.dnn.readNetFromONNX(str(OUT))
    net.setInput(dummy.numpy())
    got = net.forward()
    # 좌표는 픽셀 단위라 상대오차, 점수는 절대오차
    coord = np.abs(expected[..., :4] - got[..., :4]).max() / INPUT[0]
    score = np.abs(expected[..., 4:] - got[..., 4:]).max()
    ok = coord < 1e-4 and score < 1e-3
    print(f"출력 {expected.shape} — OpenCV 대비 좌표 {coord:.1e} 점수 {score:.1e} "
          f"{'일치' if ok else '⚠ 불일치'}")

    labels = OUT.with_suffix(".labels.json")
    labels.write_text(json.dumps([{"id": i, "name": c["name"], "korean": c.get("korean", c["name"])}
                                  for i, c in enumerate(categories)], ensure_ascii=False, indent=2),
                      encoding="utf-8")
    print(f"{OUT.name} {OUT.stat().st_size / 1e6:.1f}MB, 이름표 {labels.name}")


if __name__ == "__main__":
    main()
