"""Open Images · Commons 박스(trainset-no-lvis/)에서 물건을 rembg(U2Net)로 오려 낸다.

usage: python tools/tray-training/make_cutouts.py [최대 개수]
출력: research/tray_bench/cutouts/{train,test}/<그룹>_<id>.png + cutouts.json
"""
import hashlib
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image
from rembg import new_session, remove

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "research" / "tray_bench" / "cutouts"
LIMIT = int(sys.argv[1]) if len(sys.argv) > 1 else 1600
MIN_SIDE = 90          # 원본에서 박스 짧은 변 (px)
EDGE = 4               # 사진 가장자리에서 이만큼 떨어져 있어야 (잘리지 않은 물건)


def split_of(image_file: str) -> str:
    return "test" if int(hashlib.md5(image_file.encode()).hexdigest(), 16) % 5 == 0 else "train"


def main():
    groups, todo = {}, []
    for part in ("train", "val"):
        d = json.load(open(ROOT / "trainset-no-lvis" / f"{part}.json"))
        groups.update({c["id"]: c["name"] for c in d["categories"]})
        images = {i["id"]: i for i in d["images"]}
        for a in d["annotations"]:
            im = images[a["image_id"]]
            x, y, w, h = a["bbox"]
            if min(w, h) < MIN_SIDE or x < EDGE or y < EDGE or x + w > im["width"] - EDGE or y + h > im["height"] - EDGE:
                continue
            if w * h > 0.7 * im["width"] * im["height"]:   # 사진을 거의 다 덮는 박스는 배경이 거의 없어 오리기 어렵다
                continue
            todo.append((im["file_name"], (x, y, w, h), groups[a["category_id"]], a["id"]))
    rng = np.random.default_rng(0)
    rng.shuffle(todo)

    session = new_session("u2net")
    meta, kept = [], 0
    for file_name, (x, y, w, h), group, aid in todo:
        if kept >= LIMIT:
            break
        img = Image.open(ROOT / file_name).convert("RGB")
        pad = 0.08
        box = (max(0, x - pad * w), max(0, y - pad * h), min(img.width, x + w * (1 + pad)), min(img.height, y + h * (1 + pad)))
        crop = img.crop(tuple(int(round(v)) for v in box))
        cut = remove(crop, session=session)                         # RGBA
        alpha = np.asarray(cut)[:, :, 3]
        cover = (alpha > 128).mean()
        if not 0.15 <= cover <= 0.95:
            continue
        ys, xs = np.nonzero(alpha > 128)
        cut = cut.crop((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))   # 물건에 딱 맞게
        split = split_of(file_name)                                    # 같은 원본 사진은 한쪽에만
        out = OUT / split / f"{group}_{aid}.png"
        out.parent.mkdir(parents=True, exist_ok=True)
        cut.save(out)
        meta.append({"file": str(out.relative_to(OUT)), "group": group, "source": file_name, "split": split, "cover": round(float(cover), 3)})
        kept += 1
        if kept % 100 == 0:
            print(f"{kept} 개", flush=True)
    json.dump(meta, open(OUT / "cutouts.json", "w"), ensure_ascii=False, indent=1)
    by = {s: sum(m["split"] == s for m in meta) for s in ("train", "test")}
    print(f"오려 낸 물건 {len(meta)} 개 {by} · 후보 {len(todo)} 개 중")


if __name__ == "__main__":
    main()
