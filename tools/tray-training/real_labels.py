"""사람이 잡은 실제 트레이 정답(real_raw/labels_960.json, 960x540 좌표)으로 학습·시험 세트를 묶는다.
세션 단위로 나누고, 학습 세션 물건은 BiRefNet 으로 오려 cutouts/real/ 에도 넣는다.

usage: python tools/tray-training/real_labels.py [--train s1] [--test s2]
출력: research/tray_bench/scenes_real_train/, scenes_real_test/, cutouts/real/train/*.png
"""
import argparse
import json
import shutil
from pathlib import Path

import cv2
import numpy as np
from PIL import Image

from gen_cutouts import CUT, birefnet

ROOT = Path(__file__).resolve().parents[2]
BENCH = ROOT / "research" / "tray_bench"
W, H = 1536, 864
SCALE = W / 960
PX_PER_CM = 46.0


def build(name, keys, empties, labels):
    out = BENCH / f"scenes_real_{name}"
    shutil.rmtree(out, ignore_errors=True)
    out.mkdir(parents=True)
    coco = {"images": [], "annotations": [], "categories": [{"id": 0, "name": "item"}]}
    items = [(k, labels[k]) for k in keys] + [(f"empty/{p.stem}", []) for p in empties]
    for iid, (key, boxes) in enumerate(items):
        src = BENCH / ("real_empty/" + key.split("/", 1)[1] if key.startswith("empty/") else "real_raw/" + key)
        src = src.with_suffix(".jpg")
        img = cv2.resize(cv2.imread(str(src)), (W, H))
        fname = key.replace("/", "_") + ".jpg"
        cv2.imwrite(str(out / fname), img, [cv2.IMWRITE_JPEG_QUALITY, 95])
        coco["images"].append({"id": iid, "file_name": fname, "width": W, "height": H, "panel": key.split("/")[0]})
        for x1, y1, x2, y2, label in boxes:
            b = [round(x1 * SCALE), round(y1 * SCALE), round((x2 - x1) * SCALE), round((y2 - y1) * SCALE)]
            coco["annotations"].append({"id": len(coco["annotations"]), "image_id": iid, "category_id": 0, "bbox": b,
                                        "area": b[2] * b[3], "iscrowd": 0, "group": label, "contrast": 99.0,
                                        "touching": False, "partial": False})
    json.dump(coco, open(out / "scenes.json", "w"), ensure_ascii=False)
    print(f"{name}: 사진 {len(coco['images'])} (빈 판 {len(empties)}) · 물건 {len(coco['annotations'])}")


def cutouts(keys, labels):
    """학습 세션의 물건을 오려 cutouts.json 에 source=real 로 넣는다 (같은 물건은 처음 나온 사진 하나만)"""
    remove = birefnet()
    meta = json.load(open(CUT / "cutouts.json"))
    meta = [m for m in meta if not m["file"].startswith("real/")]
    seen, kept = set(), 0
    for key in keys:
        img = Image.open(BENCH / "real_raw" / f"{key}.jpg").convert("RGB").resize((W, H))
        for x1, y1, x2, y2, label in labels[key]:
            if label in seen:
                continue
            seen.add(label)
            pad = 0.08
            bw, bh = (x2 - x1) * SCALE, (y2 - y1) * SCALE
            box = (max(0, x1 * SCALE - pad * bw), max(0, y1 * SCALE - pad * bh), min(W, x2 * SCALE + pad * bw), min(H, y2 * SCALE + pad * bh))
            crop = img.crop(tuple(int(v) for v in box))
            cut = remove(crop)
            a = np.asarray(cut)[:, :, 3]
            ys, xs = np.nonzero(a > 128)
            if len(xs) < 200:
                continue
            cut = cut.crop((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))
            rel = f"real/train/{key.replace('/', '_')}_{label}.png"
            (CUT / rel).parent.mkdir(parents=True, exist_ok=True)
            cut.save(CUT / rel)
            long_cm = max(cut.size) / PX_PER_CM
            meta.append({"file": rel, "group": "real", "source": f"real_raw/{key}", "split": "train",
                         "size_cm": [round(long_cm * 0.85, 1), round(long_cm * 1.15, 1)], "noun": label})
            kept += 1
    json.dump(meta, open(CUT / "cutouts.json", "w"), ensure_ascii=False, indent=1)
    print(f"실제 물건 오린 것 {kept} 개")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--train", default="s1")
    ap.add_argument("--test", default="s2")
    args = ap.parse_args()
    labels = json.load(open(BENCH / "real_raw" / "labels_960.json"))
    pick = lambda sessions: [k for k in labels if k.split("/")[0] in sessions.split(",")]
    empties = sorted((BENCH / "real_empty").glob("*.jpg"))
    build("train", pick(args.train), empties[:-3], labels)
    build("test", pick(args.test), empties[-3:], labels)
    cutouts(pick(args.train), labels)


if __name__ == "__main__":
    main()
