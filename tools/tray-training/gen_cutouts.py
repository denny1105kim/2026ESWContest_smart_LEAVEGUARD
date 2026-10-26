"""gen_items.py 사진에서 물건을 BiRefNet 으로 오려 낸다. 크기·잘림·여러 덩어리·지저분한 바탕은 버린다.

usage: python tools/tray-training/gen_cutouts.py <qwen|lumina>
출력: research/tray_bench/cutouts/gen_<모델>/{train,test}/*.png + cutouts.json 에 덧붙임
"""
import json
import sys
import zlib
from pathlib import Path

import cv2
import numpy as np
import torch
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
BENCH = ROOT / "research" / "tray_bench"
CUT = BENCH / "cutouts"


def check(rgb, alpha):
    h, w = alpha.shape
    m = alpha > 128
    cover = m.mean()
    if not 0.03 <= cover <= 0.70:
        return f"크기 {cover:.2f}"
    if m[:4].any() or m[-4:].any() or m[:, :4].any() or m[:, -4:].any():
        return "가장자리"
    n, lab, stats, _ = cv2.connectedComponentsWithStats(m.astype(np.uint8))
    areas = stats[1:, cv2.CC_STAT_AREA]
    if areas.max() < 0.93 * areas.sum():
        return "여러 덩어리"
    ring = cv2.dilate(m.astype(np.uint8), np.ones((41, 41), np.uint8)) == 0
    gray = cv2.cvtColor(rgb, cv2.COLOR_RGB2GRAY).astype(np.float32)
    detail = np.abs(gray - cv2.GaussianBlur(gray, (0, 0), 6))
    if np.percentile(detail[ring], 99) > 12:
        return "바탕 지저분"
    return None


def birefnet():
    """사진 → RGBA (알파 = 물건 마스크)"""
    from transformers import AutoModelForImageSegmentation
    dev = "cuda" if torch.cuda.is_available() else "cpu"
    dtype = torch.float16 if dev == "cuda" else torch.float32
    net = AutoModelForImageSegmentation.from_pretrained("ZhengPeng7/BiRefNet", trust_remote_code=True).to(dev, dtype).eval()
    mean, std = np.array([0.485, 0.456, 0.406]), np.array([0.229, 0.224, 0.225])

    @torch.no_grad()
    def cut(img):
        rgb = np.asarray(img)
        x = (cv2.resize(rgb, (1024, 1024), interpolation=cv2.INTER_LINEAR) / 255 - mean) / std
        x = torch.from_numpy(x.transpose(2, 0, 1)[None]).to(dev, dtype)
        pred = net(x)[-1].sigmoid()[0, 0].float().cpu().numpy()
        alpha = (cv2.resize(pred, img.size, interpolation=cv2.INTER_LINEAR) * 255).clip(0, 255).astype(np.uint8)
        return Image.fromarray(np.dstack([rgb, alpha]), "RGBA")
    return cut


def main():
    model = sys.argv[1]
    src = BENCH / "gen" / model
    rows = [json.loads(line) for line in open(src / "gen.jsonl")]
    remove = birefnet()
    meta_path = CUT / "cutouts.json"
    meta = json.load(open(meta_path))
    have = {m["file"] for m in meta}
    reasons = {}
    kept = 0
    for r in rows:
        # 같은 품목·변형이 train/test 에 섞이지 않게
        split = "test" if zlib.crc32(f"{r['noun']}|{r['variant']}".encode()) % 5 == 0 else "train"
        rel = f"gen_{model}/{split}/{Path(r['file']).stem}.png"
        if rel in have:
            continue
        img = Image.open(src / r["file"]).convert("RGB")
        cut = remove(img)
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
        meta.append({"file": rel, "group": r["group"], "source": f"gen/{model}/{r['file']}", "split": split,
                     "size_cm": r["size_cm"], "noun": r["noun"], "variant": r["variant"]})
        kept += 1
    json.dump(meta, open(meta_path, "w"), ensure_ascii=False, indent=1)
    print(f"{model}: 남김 {kept} · 버림 {reasons}")


if __name__ == "__main__":
    main()
