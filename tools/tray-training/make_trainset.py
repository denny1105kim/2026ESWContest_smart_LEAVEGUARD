"""합성 장면 폴더들을 YOLOX 학습 세트(1클래스 item, COCO train.json / val.json)로 묶는다.

usage: python tools/tray-training/make_trainset.py <학습세트 이름> <장면 폴더>... [--val 0.1]
  예: python tools/tray-training/make_trainset.py trainset-tray research/tray_bench/scenes_train_gen
출력: <학습세트 이름>/train.json, val.json (file_name 은 저장소 루트 기준)
"""
import argparse
import json
import random
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("name")
    ap.add_argument("scene_dirs", nargs="+")
    ap.add_argument("--val", type=float, default=0.1)
    args = ap.parse_args()
    images, anns = [], []
    for d in args.scene_dirs:
        d = ROOT / d
        coco = json.load(open(d / "scenes.json"))
        base = len(images)
        remap = {}
        for im in coco["images"]:
            remap[im["id"]] = base + len(remap)
            images.append({"id": remap[im["id"]], "file_name": str((d / im["file_name"]).relative_to(ROOT)),
                           "width": im["width"], "height": im["height"]})
        for a in coco["annotations"]:
            anns.append({"image_id": remap[a["image_id"]], "category_id": 0, "bbox": a["bbox"], "area": a["area"], "iscrowd": 0})
    random.Random(0).shuffle(images)
    n_val = int(len(images) * args.val)
    out = ROOT / args.name
    out.mkdir(exist_ok=True)
    for part, ims in (("val", images[:n_val]), ("train", images[n_val:])):
        ids = {im["id"] for im in ims}
        part_anns = [dict(a, id=i) for i, a in enumerate(a for a in anns if a["image_id"] in ids)]
        json.dump({"images": ims, "annotations": part_anns, "categories": [{"id": 0, "name": "item"}]}, open(out / f"{part}.json", "w"))
        print(f"{part}: 사진 {len(ims)} · 물건 {len(part_anns)}")


if __name__ == "__main__":
    main()
