"""위에서 찍은 합성 장면을 비스듬한 카메라 화면으로 원근 변환하고, 판 밖은 실제 빈 판 사진으로 채운다.
정답 박스는 네 꼭짓점을 옮긴 바깥 네모. 화면에 25% 미만으로 남거나 아주 작으면 뺀다.

usage: python tools/tray-training/warp_oblique.py <장면폴더,...> <출력폴더> <장 수> <빈 판 사진> [--seed 0]
"""
import argparse
import json
import random
from pathlib import Path

import cv2
import numpy as np

ROOT = Path(__file__).resolve().parents[2]
# 판 TL TR BR BL → 화면 (1536×864). 먼 두 꼭짓점은 실측, 가까운 변은 화면 밖이라 연장선
QUAD = np.float32([[412, 16], [1154, 68], [1729, 1150], [-294, 1150]])
OUT = (1536, 864)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('src'); ap.add_argument('out'); ap.add_argument('n', type=int); ap.add_argument('bg')
    ap.add_argument('--seed', type=int, default=0)
    a = ap.parse_args()
    rng = random.Random(a.seed)
    bg = cv2.imread(a.bg)
    items = []
    for d in a.src.split(','):
        d = ROOT / 'research' / 'tray_bench' / d
        j = json.load(open(d / 'scenes.json'))
        anns = {}
        for an in j['annotations']:
            anns.setdefault(an['image_id'], []).append(an['bbox'])
        items += [(d / im['file_name'], im['width'], im['height'], anns.get(im['id'], [])) for im in j['images']]
    rng.shuffle(items)
    out = ROOT / 'research' / 'tray_bench' / a.out
    out.mkdir(parents=True, exist_ok=True)
    images, annotations = [], []
    for k, (path, w, h, boxes) in enumerate(items[: a.n]):
        im = cv2.imread(str(path))
        # 꼭짓점을 조금씩 흔든다 (카메라가 밀린 만큼 · 판 위치)
        q = QUAD + np.float32([[rng.uniform(-14, 14), rng.uniform(-14, 14)] for _ in range(4)])
        H = cv2.getPerspectiveTransform(np.float32([[0, 0], [w, 0], [w, h], [0, h]]), q)
        warped = cv2.warpPerspective(im, H, OUT, flags=cv2.INTER_AREA, borderMode=cv2.BORDER_CONSTANT)
        mask = cv2.warpPerspective(np.full((h, w), 255, np.uint8), H, OUT, flags=cv2.INTER_NEAREST)
        base = bg.copy()
        # 판 밝기를 실제 빈 판과 맞춘다 (먼 쪽이 밝다): 판 안 평균을 실제 판 평균에 맞춤
        m = mask > 0
        gain = (base[m].mean(0) + 1) / (warped[m].mean(0) + 1)
        warped = np.clip(warped.astype(np.float32) * gain.clip(0.6, 1.6), 0, 255).astype(np.uint8)
        soft = cv2.GaussianBlur(mask, (5, 5), 0)[..., None] / 255.0
        frame = (warped * soft + base * (1 - soft)).astype(np.uint8)
        name = f'obl_{a.seed}_{k:05d}.jpg'
        cv2.imwrite(str(out / name), frame, [cv2.IMWRITE_JPEG_QUALITY, 90])
        iid = a.seed * 100000 + k
        images.append({'id': iid, 'file_name': name, 'width': OUT[0], 'height': OUT[1]})
        for x, y, bw, bh in boxes:
            pts = cv2.perspectiveTransform(np.float32([[[x, y], [x + bw, y], [x + bw, y + bh], [x, y + bh]]]), H)[0]
            x1, y1 = pts.min(0); x2, y2 = pts.max(0)
            full = (x2 - x1) * (y2 - y1)
            cx1, cy1, cx2, cy2 = max(0, x1), max(0, y1), min(OUT[0], x2), min(OUT[1], y2)
            if cx2 <= cx1 or cy2 <= cy1: continue
            vis = (cx2 - cx1) * (cy2 - cy1)
            if vis < 0.25 * full or min(cx2 - cx1, cy2 - cy1) < 12: continue
            annotations.append({'id': len(annotations), 'image_id': iid, 'category_id': 0,
                                'bbox': [float(cx1), float(cy1), float(cx2 - cx1), float(cy2 - cy1)], 'area': float(vis), 'iscrowd': 0})
    json.dump({'images': images, 'annotations': annotations, 'categories': [{'id': 0, 'name': 'item'}]}, open(out / 'scenes.json', 'w'))
    print(a.out, len(images), 'images', len(annotations), 'boxes')


if __name__ == '__main__':
    main()
