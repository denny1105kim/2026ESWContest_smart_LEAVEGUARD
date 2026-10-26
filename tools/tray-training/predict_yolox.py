"""YOLOX-Nano 로 트레이 장면의 박스를 뽑는다 (클래스 무시 NMS, 점수 0.01 이상 전부 — 자르기는 eval_boxes.py).

usage: python tools/tray-training/predict_yolox.py <이름> <체크포인트.pth> <클래스 수> [--size 416] [--split test]
출력: research/tray_bench/pred/yolox_<이름>.json  {"파일": [[x, y, w, h, 점수], ...]}
"""
import argparse
import json
import sys
import time
from pathlib import Path

import cv2
import numpy as np
import torch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "vendor" / "YOLOX"))
from yolox.data.data_augment import preproc                 # noqa: E402
from yolox.models import YOLOX, YOLOPAFPN, YOLOXHead          # noqa: E402
from yolox.utils import postprocess                           # noqa: E402

BENCH = ROOT / "research" / "tray_bench"


def load(ckpt_path, num_classes):
    backbone = YOLOPAFPN(0.33, 0.25, in_channels=[256, 512, 1024], act="silu", depthwise=True)
    model = YOLOX(backbone, YOLOXHead(num_classes, 0.25, in_channels=[256, 512, 1024], act="silu", depthwise=True))
    for m in model.modules():                      # train_yolox.build_model 과 같은 BN 값
        if isinstance(m, torch.nn.BatchNorm2d):
            m.eps, m.momentum = 1e-3, 0.03
    ckpt = torch.load(ckpt_path, map_location="cpu", weights_only=False)
    state = ckpt.get("model", ckpt.get("ema", ckpt))
    missing, unexpected = model.load_state_dict(state, strict=False)
    assert not missing, missing[:5]
    return model.cuda().eval()


@torch.no_grad()
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("name")
    ap.add_argument("ckpt")
    ap.add_argument("classes", type=int)
    ap.add_argument("--size", type=int, default=416)
    ap.add_argument("--split", default="test")
    args = ap.parse_args()
    model = load(ROOT / args.ckpt, args.classes)
    scene_dir = BENCH / f"scenes_{args.split}"
    gt = json.load(open(scene_dir / "scenes.json"))
    out, t = {}, 0.0
    for im in gt["images"]:
        img = cv2.imread(str(scene_dir / im["file_name"]))
        padded, ratio = preproc(img, (args.size, args.size))
        t0 = time.time()
        pred = model(torch.from_numpy(padded).unsqueeze(0).cuda())
        res = postprocess(pred, args.classes, conf_thre=0.01, nms_thre=0.5, class_agnostic=True)[0]
        t += time.time() - t0
        boxes = []
        if res is not None:
            for x1, y1, x2, y2, obj, cls_conf, _ in res.cpu().numpy():
                x1, y1, x2, y2 = (v / ratio for v in (x1, y1, x2, y2))
                boxes.append([round(float(x1)), round(float(y1)), round(float(x2 - x1)), round(float(y2 - y1)), round(float(obj * cls_conf), 4)])
        out[im["file_name"]] = boxes
    (BENCH / "pred").mkdir(exist_ok=True)
    json.dump(out, open(BENCH / "pred" / f"yolox_{args.name}.json", "w"))
    print(f"{args.name}: {len(out)} 장 · GPU {t / len(out) * 1000:.1f} ms/장")


if __name__ == "__main__":
    main()
