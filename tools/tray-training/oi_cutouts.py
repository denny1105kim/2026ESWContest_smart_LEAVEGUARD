"""Open Images V7 분할 마스크로 실제 사진 속 물건을 오린다 (사진 CC BY 2.0 · 마스크 CC BY 4.0).

준비: research/oi_seg/{validation,test}-seg.csv (https://storage.googleapis.com/openimages/v5/{split}-annotations-object-segmentation.csv),
      openimages/_cache/classes.csv. 사진과 마스크 zip 은 실행 중 받는다.
usage: python tools/tray-training/oi_cutouts.py [--per-class 400]
출력: research/tray_bench/cutouts/oi/{train,test}/*.png + cutouts.json 에 덧붙임
"""
import argparse
import csv
import io
import json
import random
import urllib.request
import zipfile
from collections import defaultdict
from pathlib import Path

import cv2
import numpy as np
from PIL import Image

from gen_cutouts import CUT, check

ROOT = Path(__file__).resolve().parents[2]
SEG = ROOT / "research" / "oi_seg"
CLASSES_CSV = ROOT / "openimages" / "_cache" / "classes.csv"
MASK_URL = "https://storage.googleapis.com/openimages/v5/{split}-masks/{split}-masks-{c}.zip"
IMG_URL = "https://open-images-dataset.s3.amazonaws.com/{split}/{id}.jpg"

# Open Images 클래스 → (그룹, 긴 변 cm). Lipstick 은 입술 사진이 섞여 있어 뺐다
CLASSES = {
    "Mobile phone": ("phone", (13, 17)),
    "Watch": ("watch", (4, 22)),
    "Coin": ("misc", (2, 3)),
    "Remote control": ("misc", (12, 20)),
    "Pen": ("misc", (12, 15)),
    "Computer mouse": ("charger", (9, 12)),
    "Calculator": ("misc", (10, 16)),
    "Camera": ("misc", (8, 14)),
    "Toy": ("misc", (5, 18)),
    "Teddy bear": ("misc", (10, 20)),
    "Pencil case": ("misc", (15, 22)),
    "Flashlight": ("misc", (8, 16)),
    "Torch": ("misc", (8, 16)),
    "Bottle": ("bottle", (12, 22)),
    "Glove": ("misc", (16, 24)),
    "Envelope": ("misc", (16, 23)),
}


def masks_zip(split: str, c: str) -> zipfile.ZipFile:
    path = SEG / f"{split}-masks-{c}.zip"
    if not path.exists():
        urllib.request.urlretrieve(MASK_URL.format(split=split, c=c), path)
    return zipfile.ZipFile(path)


def image(split: str, image_id: str) -> np.ndarray | None:
    cache = SEG / "images" / f"{image_id}.jpg"
    if not cache.exists():
        cache.parent.mkdir(parents=True, exist_ok=True)
        try:
            urllib.request.urlretrieve(IMG_URL.format(split=split, id=image_id), cache)
        except Exception:
            return None
    img = cv2.imread(str(cache))
    return None if img is None else cv2.cvtColor(img, cv2.COLOR_BGR2RGB)


def cut(rgb: np.ndarray, mask: np.ndarray) -> tuple[np.ndarray, np.ndarray] | None:
    """마스크(사진 크기) → 물건 둘레 여백 15% 로 자른 RGB · 알파. 가장자리는 1px 깎고 살짝 흐리게"""
    m = (mask > 0).astype(np.uint8)
    n, lab, st, _ = cv2.connectedComponentsWithStats(m)
    if n < 2:
        return None
    areas = st[1:, cv2.CC_STAT_AREA]
    i = 1 + int(areas.argmax())
    if areas.max() < 0.93 * areas.sum():
        return None
    m = (lab == i).astype(np.uint8)
    m = cv2.morphologyEx(m, cv2.MORPH_CLOSE, np.ones((5, 5), np.uint8))
    m = cv2.erode(m, np.ones((3, 3), np.uint8))
    x, y, w, h = st[i, :4]
    px, py = int(w * 0.15) + 6, int(h * 0.15) + 6
    x0, y0, x1, y1 = max(0, x - px), max(0, y - py), min(rgb.shape[1], x + w + px), min(rgb.shape[0], y + h + py)
    alpha = cv2.GaussianBlur(m[y0:y1, x0:x1].astype(np.float32) * 255, (0, 0), 0.8)
    return rgb[y0:y1, x0:x1], alpha.astype(np.uint8)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--per-class", type=int, default=400, help="클래스마다 최대 몇 개 (split 마다)")
    args = ap.parse_args()
    names = {r[0]: r[1] for r in csv.reader(open(CLASSES_CSV))}
    meta_path = CUT / "cutouts.json"
    meta = json.load(open(meta_path))
    done = {m["source"] for m in meta}
    rng = random.Random(0)
    added = defaultdict(int)
    for split, out_split in (("validation", "train"), ("test", "test")):
        rows = defaultdict(list)
        for r in csv.DictReader(open(SEG / f"{split}-seg.csv")):
            name = names.get(r["LabelName"])
            if name not in CLASSES:
                continue
            x0, x1, y0, y1 = (float(r[k]) for k in ("BoxXMin", "BoxXMax", "BoxYMin", "BoxYMax"))
            if x0 < 0.01 or y0 < 0.01 or x1 > 0.99 or y1 > 0.99:   # 사진 가장자리에 닿음 = 잘린 물건
                continue
            rows[name].append(r)
        out = CUT / "oi" / out_split
        out.mkdir(parents=True, exist_ok=True)
        zips = {}
        for name, rs in rows.items():
            group, size = CLASSES[name]
            rng.shuffle(rs)
            kept = why_n = 0
            for r in rs:
                if kept >= args.per_class:
                    break
                src = f"oi/{r['ImageID']}/{r['MaskPath']}"
                if src in done:
                    continue
                rgb = image(split, r["ImageID"])
                if rgb is None:
                    continue
                H, W = rgb.shape[:2]
                bw, bh = (float(r["BoxXMax"]) - float(r["BoxXMin"])) * W, (float(r["BoxYMax"]) - float(r["BoxYMin"])) * H
                if max(bw, bh) < 96:
                    continue
                c = r["MaskPath"][0]
                z = zips.get(c) or zips.setdefault(c, masks_zip(split, c))
                mask = np.array(Image.open(io.BytesIO(z.read(r["MaskPath"]))).convert("L").resize((W, H), Image.NEAREST))
                if (mask > 0).sum() < 0.30 * bw * bh:                  # 박스에 비해 마스크가 작다 = 많이 가려짐
                    continue
                res = cut(rgb, mask)
                if res is None:
                    continue
                crop, alpha = res
                why = check(crop, alpha)
                if why and why != "바탕 지저분":                       # 실제 사진이라 바탕 검사는 건너뛴다
                    why_n += 1
                    continue
                file = f"oi/{out_split}/{name.lower().replace(' ', '_')}_{r['MaskPath'][:-4]}.png"
                Image.fromarray(np.dstack([crop, alpha])).save(CUT / file)
                meta.append({"file": file, "group": group, "source": src, "split": out_split,
                             "size_cm": list(size), "noun": name})
                kept += 1
                added[(out_split, name)] += 1
            print(f"{split:10s} {name:15s} 후보 {len(rs):4d} → {kept:3d} (검사 탈락 {why_n})", flush=True)
        json.dump(meta, open(meta_path, "w"), ensure_ascii=False, indent=1)
    print(f"추가 {sum(added.values())} 개 · cutouts.json {len(meta)} 개")


if __name__ == "__main__":
    main()
