"""실제 트레이 시험 세트: 노드의 /snapshot.jpg 를 받아 모으고(capture), 물건을 하나씩 올린 차이로 정답 박스를 만든다(label).
세션마다 빈 판(00.jpg)부터 시작해 물건을 하나씩 올리고 엔터, 끝나면 q.

usage: python tools/tray-training/real_capture.py capture <세션> --url http://<Pi4IP>:8080
       python tools/tray-training/real_capture.py label <세션>... [--roi 20,20,1100,650] [--threshold 28]
출력: research/tray_bench/scenes_real/ (1536x864 사진 + scenes.json, _check/ 에 박스 그린 확인용)
"""
import argparse
import json
import urllib.request
from pathlib import Path

import cv2
import numpy as np

ROOT = Path(__file__).resolve().parents[2]
BENCH = ROOT / "research" / "tray_bench"
RAW = BENCH / "real_raw"
OUT = BENCH / "scenes_real"
W, H = 1536, 864


def capture(session, url):
    d = RAW / session
    d.mkdir(parents=True, exist_ok=True)
    i = len(list(d.glob("*.jpg")))
    while True:
        what = "빈 판" if i == 0 else f"물건 {i}개째"
        cmd = input(f"[{session}] {what} 올리고 엔터 (q 끝): ").strip()
        if cmd == "q":
            break
        data = urllib.request.urlopen(f"{url}/snapshot.jpg", timeout=10).read()
        (d / f"{i:02d}.jpg").write_bytes(data)
        print(f"  저장 {d / f'{i:02d}.jpg'} ({len(data) // 1024} KB)")
        i += 1


def new_object(prev, cur, threshold):
    """직전 사진과 달라진 곳 = 방금 올린 물건 (+그림자). 가장 큰 덩어리 무리의 네모"""
    a = cv2.GaussianBlur(prev, (0, 0), 2).astype(np.int16)
    b = cv2.GaussianBlur(cur, (0, 0), 2).astype(np.int16)
    diff = np.abs(a - b).max(2).astype(np.uint8)
    # 그림자 빼기: 밝기만 고르게 어두워지고(0.45~0.9배) 색은 그대로인 곳
    la = cv2.cvtColor(prev, cv2.COLOR_BGR2Lab).astype(np.float32)
    lb = cv2.cvtColor(cur, cv2.COLOR_BGR2Lab).astype(np.float32)
    ratio = (lb[..., 0] + 1) / (la[..., 0] + 1)
    chroma = np.hypot(lb[..., 1] - la[..., 1], lb[..., 2] - la[..., 2])
    shadow = (ratio > 0.45) & (ratio < 0.9) & (chroma < 4) & (la[..., 0] > 40)
    mask = ((diff > threshold) & ~shadow).astype(np.uint8)
    mask = cv2.morphologyEx(mask, cv2.MORPH_OPEN, np.ones((3, 3), np.uint8))
    mask = cv2.morphologyEx(mask, cv2.MORPH_CLOSE, np.ones((9, 9), np.uint8))
    n, lab, stats, _ = cv2.connectedComponentsWithStats(mask)
    if n <= 1:
        return None
    keep = [i for i in range(1, n) if stats[i, cv2.CC_STAT_AREA] > 0.0008 * mask.size]
    if not keep:
        return None
    big = max(keep, key=lambda i: stats[i, cv2.CC_STAT_AREA])
    bx, by, bw, bh = stats[big, :4]
    # 가장 큰 덩어리 가까이(긴 변의 30% 안) 있는 조각만 같은 물건으로 (열쇠+고리, 케이블)
    reach = 0.3 * max(bw, bh)
    x0, y0, x1, y1 = bx, by, bx + bw, by + bh
    for i in keep:
        x, y, w, h = stats[i, :4]
        if x < x1 + reach and x + w > x0 - reach and y < y1 + reach and y + h > y0 - reach:
            x0, y0, x1, y1 = min(x0, x), min(y0, y), max(x1, x + w), max(y1, y + h)
    return [int(x0), int(y0), int(x1 - x0), int(y1 - y0)]


def label(sessions, roi, threshold):
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "_check").mkdir(exist_ok=True)
    x, y, w, h = roi
    coco = {"images": [], "annotations": [], "categories": [{"id": 0, "name": "item"}]}
    aid = 0
    for s in sessions:
        frames = sorted((RAW / s).glob("*.jpg"))
        crops = [cv2.resize(cv2.imread(str(f))[y:y + h, x:x + w], (W, H), interpolation=cv2.INTER_AREA) for f in frames]
        boxes = []
        for k, img in enumerate(crops):
            if k > 0:
                b = new_object(crops[k - 1], img, threshold)
                if b is None:
                    print(f"  {s}/{frames[k].name}: 새 물건을 못 찾음 — 이 사진부터는 정답이 하나 모자랄 수 있다")
                else:
                    boxes.append(b)
            name = f"{s}_{k:02d}.jpg"
            cv2.imwrite(str(OUT / name), img, [cv2.IMWRITE_JPEG_QUALITY, 95])
            iid = len(coco["images"])
            coco["images"].append({"id": iid, "file_name": name, "width": W, "height": H, "panel": s})
            vis = img.copy()
            for b in boxes:
                coco["annotations"].append({"id": aid, "image_id": iid, "category_id": 0, "bbox": b, "area": b[2] * b[3],
                                            "iscrowd": 0, "group": "real", "contrast": 99.0, "touching": False, "partial": False})
                aid += 1
                cv2.rectangle(vis, (b[0], b[1]), (b[0] + b[2], b[1] + b[3]), (0, 255, 0), 3)
            cv2.imwrite(str(OUT / "_check" / name), cv2.resize(vis, (768, 432)))
        print(f"{s}: 사진 {len(crops)} · 물건 {len(boxes)}")
    # 붙음 표시 (분석용)
    by = {}
    for a in coco["annotations"]:
        by.setdefault(a["image_id"], []).append(a)
    for anns in by.values():
        for a in anns:
            ax, ay, aw, ah = a["bbox"]
            a["touching"] = any(max(bx - (ax + aw), ax - (bx + bw), by_ - (ay + ah), ay - (by_ + bh)) < 14
                                for o in anns if o is not a for bx, by_, bw, bh in [o["bbox"]])
    json.dump(coco, open(OUT / "scenes.json", "w"), ensure_ascii=False)
    print(f"시험 세트: 사진 {len(coco['images'])} · 물건 {aid} → {OUT}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["capture", "label"])
    ap.add_argument("sessions", nargs="+")
    ap.add_argument("--url", default="http://192.168.0.51:8080")
    ap.add_argument("--roi", default="20,20,1100,650")
    ap.add_argument("--threshold", type=int, default=28)
    args = ap.parse_args()
    if args.cmd == "capture":
        capture(args.sessions[0], args.url)
    else:
        label(args.sessions, [int(v) for v in args.roi.split(",")], args.threshold)


if __name__ == "__main__":
    main()
