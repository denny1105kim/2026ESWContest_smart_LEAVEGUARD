"""Amazon Berkeley Objects (CC BY 4.0) 상품 사진에서 트레이 소지품을 골라 오린다 (rembg IS-Net).

준비: research/abo/ 에 abo-listings.tar, abo-images-small.tar 를 풀어 둔다 (https://amazon-berkeley-objects.s3.amazonaws.com/index.html)
usage: python tools/tray-training/abo_cutouts.py
출력: research/tray_bench/cutouts/abo/{train,test}/*.png + cutouts.json 에 덧붙임
"""
import csv
import gzip
import json
import zlib
from pathlib import Path

import numpy as np
from PIL import Image
from rembg import new_session, remove

from gen_cutouts import CUT, check

ROOT = Path(__file__).resolve().parents[2]
ABO = ROOT / "research" / "abo"

# 상품 종류 → (그룹, 긴 변 cm, 최대 상품 수). 묶음 사진이 많은 종류(펜·티슈·배터리 등)는 뺐다
TYPES = {
    "CELLULAR_PHONE_CASE": ("phone", (14, 17), 500),
    "PHONE": ("phone", (14, 17), 50),
    "WALLET": ("wallet", (9, 19), 200),
    "HEADPHONES": ("audio", (4, 18), 200),
    "WIRELESS_ACCESSORY": ("charger", (5, 14), 200),
    "CHARGING_ADAPTER": ("charger", (4, 9), 200),
    "ELECTRONIC_ADAPTER": ("charger", (4, 10), 150),
    "FLASH_MEMORY": ("charger", (3, 6), 50),
    "FLASH_DRIVE": ("charger", (3, 6), 20),
    "INPUT_MOUSE": ("charger", (9, 12), 50),
    "ELECTRONIC_CABLE": ("charger", (8, 14), 20),
    "PHONE_ACCESSORY": ("charger", (4, 12), 60),
    "WATCH": ("watch", (17, 23), 50),
    "EYEWEAR": ("eyewear", (13, 16), 100),
    "SUNGLASSES": ("eyewear", (13, 15), 30),
    "SKIN_MOISTURIZER": ("toiletry", (6, 15), 200),
    "SUNSCREEN": ("toiletry", (8, 15), 50),
    "LIP_COLOR": ("toiletry", (6, 8.5), 50),
    "LIP_BALM": ("toiletry", (5, 7.5), 10),
    "COSMETIC_CASE": ("toiletry", (8, 18), 60),
    "HAIR_COMB": ("toiletry", (10, 18), 10),
    "PERSONAL_PILL_DISPENSER": ("toiletry", (6, 12), 10),
    "BADGE_HOLDER": ("card", (9, 14), 10),
    "RING": ("misc", (2, 3), 100),
    "FINERING": ("misc", (2, 3), 100),
    "BRACELET": ("misc", (6, 8), 80),
}


def main():
    images = {}
    with gzip.open(ABO / "images" / "metadata" / "images.csv.gz", "rt") as f:
        for r in csv.DictReader(f):
            images[r["image_id"]] = r["path"]
    picked, count = [], {}
    for path in sorted((ABO / "listings" / "metadata").glob("*.json.gz")):
        for line in gzip.open(path, "rt"):
            d = json.loads(line)
            for p in d.get("product_type", []):
                t = p["value"]
                if t in TYPES and count.get(t, 0) < TYPES[t][2] and d.get("main_image_id") in images:
                    count[t] = count.get(t, 0) + 1
                    ids = [d["main_image_id"]] + d.get("other_image_id", [])[:2]
                    picked += [(t, d["item_id"], i) for i in ids if i in images]
                    break
    print(f"상품 {sum(count.values())} 개 · 사진 {len(picked)} 장", flush=True)

    session = new_session("isnet-general-use")        # 흰 바탕 작은 사진이라 BiRefNet 보다 가벼운 것으로 충분
    meta = json.load(open(CUT / "cutouts.json"))
    have = {m["file"] for m in meta}
    kept, reasons = 0, {}
    for t, item, image_id in picked:
        split = "test" if zlib.crc32(item.encode()) % 5 == 0 else "train"   # 같은 상품은 한쪽에만
        rel = f"abo/{split}/{t.lower()}_{image_id}.png"
        if rel in have:
            continue
        img = Image.open(ABO / "images" / "small" / images[image_id]).convert("RGB")
        if min(img.size) < 120:
            continue
        cut = remove(img, session=session)
        alpha = np.asarray(cut)[:, :, 3]
        why = check(np.asarray(img), alpha)
        if why:
            reasons[why.split()[0]] = reasons.get(why.split()[0], 0) + 1
            continue
        ys, xs = np.nonzero(alpha > 128)
        cut = cut.crop((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))
        out = CUT / rel
        out.parent.mkdir(parents=True, exist_ok=True)
        cut.save(out)
        group, size_cm, _ = TYPES[t]
        meta.append({"file": rel, "group": group, "source": f"abo/{item}/{image_id}", "split": split,
                     "size_cm": size_cm, "noun": t})
        kept += 1
        if kept % 200 == 0:
            print(f"{kept} 개", flush=True)
            json.dump(meta, open(CUT / "cutouts.json", "w"), ensure_ascii=False, indent=1)
    json.dump(meta, open(CUT / "cutouts.json", "w"), ensure_ascii=False, indent=1)
    print(f"abo: 남김 {kept} · 버림 {reasons}")


if __name__ == "__main__":
    main()
