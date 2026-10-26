"""트레이 장면 합성: 회색 판 바탕 + 오린 물건(실제 크기 cm 축척) + 그림자·조명. 정답 박스는 COCO.

usage: python tools/tray-training/make_scenes.py <train|test> <장면 수> [--sources orig,gen_lumina,abo,oi,real] [--out 이름]
         [--gen-bg 비율] [--real-bg 비율] [--real-bg-dir 폴더] [--empty 비율] [--distract 비율]
         [--stack 비율] [--dark 비율] [--camera] [--frame WxH] [--px-per-cm N] [--seed N]
  배경 기본은 research/tray_bench/real/snap.jpg 에서 물건을 지운 판. --gen-bg/--real-bg 는 생성 바탕·실제 빈 판 비율
  empty 물건 없는 장면, distract 이음새·반사광 같은 "물건 아님" 무늬, stack 포개기, dark 어두운 물건으로 바꾸기
  camera 축척·노이즈·흐림·JPEG·비네팅을 장면마다 바꾼다
출력: research/tray_bench/scenes_<split>[_이름]/*.jpg + scenes.json
"""
import argparse
import json
from pathlib import Path

import cv2
import numpy as np

ROOT = Path(__file__).resolve().parents[2]
BENCH = ROOT / "research" / "tray_bench"
W, H = 1536, 864                  # --frame 로 바꾼다
PX_PER_CM = 46.0
BAND = 0.05                       # 판넬 가장자리 띠, 물건은 이 안쪽에만 둔다

# 그룹별 긴 변 실제 크기 (cm). 없는 그룹은 트레이에 안 올리는 것
SIZE_CM = {"phone": (14, 17), "wallet": (9, 19), "key": (5, 9), "card": (8.5, 9), "audio": (5, 8),
           "eyewear": (13, 15), "watch": (6, 22), "charger": (4, 10), "toiletry": (5, 15), "tissue": (8, 12),
           "bottle": (12, 20)}


def background():
    img = cv2.imread(str(BENCH / "real" / "snap.jpg"))
    mask = np.zeros(img.shape[:2], np.uint8)
    cv2.rectangle(mask, (325, 220), (1065, 610), 255, -1)       # 휴대폰 자리 (그림자 포함)
    # 지운 자리: 밝기(저주파)는 2차 곡면으로, 결(고주파)은 빈 곳의 판 결을 복사해 채운다
    f = img.astype(np.float32)
    low = cv2.GaussianBlur(f, (0, 0), 25)
    high = f - low
    hh, ww = mask.shape
    yy, xx = np.mgrid[0:hh:8, 0:ww:8]
    keep = mask[::8, ::8] == 0
    X = lambda x, y: np.stack([np.ones_like(x), x, y, x * x, x * y, y * y], -1) / [1, ww, hh, ww * ww, ww * hh, hh * hh]
    A = X(xx[keep].astype(np.float64), yy[keep].astype(np.float64))
    gy, gx = np.mgrid[0:hh, 0:ww]
    G = X(gx.astype(np.float64), gy.astype(np.float64))
    low_filled = np.stack([G @ np.linalg.lstsq(A, low[::8, ::8, c][keep], rcond=None)[0] for c in range(3)], -1).astype(np.float32)
    tex = high[20:220, 20:330]                                  # 물건 없는 판 왼쪽 위
    reps = (int(np.ceil(img.shape[0] / tex.shape[0])) + 1, int(np.ceil(img.shape[1] / tex.shape[1])) + 1, 1)
    tex_full = np.tile(np.concatenate([tex, tex[:, ::-1]], 1), reps)[: img.shape[0], : img.shape[1]]
    m = (cv2.GaussianBlur(mask.astype(np.float32) / 255, (0, 0), 20))[..., None]
    clean = np.clip(f * (1 - m) + (low_filled + tex_full) * m, 0, 255).astype(np.uint8)
    panel = clean[20:670, 20:1120]                              # 설정한 판넬 범위
    return cv2.resize(panel, (W, H), interpolation=cv2.INTER_LINEAR)


def vary_panel(bg, rng):
    kind = rng.choice(["gray", "dark", "light"], p=[0.5, 0.25, 0.25])
    f = {"gray": 1.0, "dark": 0.45, "light": 1.9}[kind] * rng.uniform(0.85, 1.15)
    out = bg.astype(np.float32) * f
    gx, gy = rng.uniform(-30, 30), rng.uniform(-30, 30)          # 조명 기울기
    xx, yy = np.meshgrid(np.linspace(-0.5, 0.5, W), np.linspace(-0.5, 0.5, H))
    out += (gx * xx + gy * yy)[..., None]
    return np.clip(out, 0, 255), kind


def load_cutouts(split, sources):
    meta = json.load(open(BENCH / "cutouts" / "cutouts.json"))
    source = lambda m: "orig" if m["file"].split("/")[0] in ("train", "test") else m["file"].split("/")[0]
    return [m for m in meta if m["split"] == split and source(m) in sources and ("size_cm" in m or m["group"] in SIZE_CM)]


def harmonize(rgba, panel_l, rng):
    """붙인 티 줄이기: 판 조명에 맞춰 물건 밝기를 조금 옮기고, 카메라처럼 살짝 흐리게, 가장자리 부드럽게"""
    rgb = rgba[:, :, :3].astype(np.float32)
    rgb *= np.clip(panel_l / 128, 0.55, 1.25) ** rng.uniform(0.3, 0.7)
    rgb *= rng.uniform(0.9, 1.1, 3)                                # 화이트밸런스 차이
    sigma = rng.uniform(0.4, 1.3)
    rgb = cv2.GaussianBlur(rgb, (0, 0), sigma)
    a = cv2.GaussianBlur(rgba[:, :, 3].astype(np.float32), (0, 0), sigma * 0.8)
    return np.dstack([np.clip(rgb, 0, 255), a]).astype(np.uint8)


def gen_backgrounds():
    return sorted((BENCH / "backgrounds").glob("gen_*.jpg"))


def gen_panel(path, rng):
    img = cv2.resize(cv2.imread(str(path)), (W, H), interpolation=cv2.INTER_LINEAR).astype(np.float32)
    if rng.random() < 0.5:
        img = img[:, ::-1]
    if rng.random() < 0.5:
        img = img[::-1]
    return np.clip(img * rng.uniform(0.8, 1.2), 0, 255)


def distract(img, rng):
    """판 위의 '물건 아닌' 무늬를 1~4 개 그린다 (정답 없음)"""
    f = img.astype(np.float32)
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    level = float(f.mean())
    for _ in range(int(rng.integers(1, 5))):
        kind = rng.choice(["seam", "fold", "grid", "tape", "glare", "dust", "scratch"], p=[0.2, 0.2, 0.12, 0.12, 0.16, 0.1, 0.1])
        if kind in ("seam", "fold"):
            # 화면을 가로지르는 직선 (약간 기울게). 이음새 = 가는 선, 접힘 = 양쪽 밝기 차 + 경계 하이라이트
            ang = rng.uniform(-0.6, 0.6) + (0 if rng.random() < 0.5 else np.pi / 2)
            cx, cy = rng.uniform(0.15, 0.85) * W, rng.uniform(0.15, 0.85) * H
            d = (xx - cx) * np.sin(ang) - (yy - cy) * np.cos(ang)
            if kind == "seam":
                width = rng.uniform(1, 4)
                f += (np.exp(-(d / width) ** 2) * rng.choice([-1, 1]) * rng.uniform(10, 45))[..., None]
            else:
                f *= np.where(d > 0, rng.uniform(0.82, 1.18), 1.0)[..., None]
                f += (np.exp(-(d / rng.uniform(1.5, 4)) ** 2) * rng.uniform(8, 30))[..., None]
        elif kind == "grid":
            step = rng.uniform(40, 160)
            ph = rng.uniform(0, step, 2)
            g = (np.abs(((xx + ph[0]) % step) - step / 2) > step / 2 - 1.2) | (np.abs(((yy + ph[1]) % step) - step / 2) > step / 2 - 1.2)
            f += (g * rng.choice([-1, 1]) * rng.uniform(5, 20)).astype(np.float32)[..., None]
        elif kind == "tape":
            w, h = rng.uniform(60, 500), rng.uniform(25, 70)
            if rng.random() < 0.5:
                w, h = h, w
            rect = ((rng.uniform(0, W), rng.uniform(0, H)), (w, h), rng.uniform(0, 180))
            m = np.zeros((H, W), np.uint8)
            cv2.fillPoly(m, [cv2.boxPoints(rect).astype(np.int32)], 1)
            m = cv2.GaussianBlur(m.astype(np.float32), (0, 0), 1.2)
            f += (m * rng.uniform(-18, 18))[..., None]
        elif kind == "glare":
            cx, cy, r = rng.uniform(0, W), rng.uniform(0, H), rng.uniform(120, 600)
            f += (np.exp(-((xx - cx) ** 2 + (yy - cy) ** 2) / (2 * r * r)) * rng.uniform(20, 90))[..., None]
        elif kind == "dust":
            n = int(rng.integers(20, 200))
            for _ in range(n):
                cv2.circle(f, (int(rng.uniform(0, W)), int(rng.uniform(0, H))), int(rng.integers(1, 3)),
                           (level + rng.uniform(15, 60),) * 3, -1)
        else:
            p0 = (int(rng.uniform(0, W)), int(rng.uniform(0, H)))
            p1 = (p0[0] + int(rng.normal(0, 200)), p0[1] + int(rng.normal(0, 200)))
            cv2.line(f, p0, p1, (level + rng.uniform(15, 50),) * 3, 1, cv2.LINE_AA)
    return np.clip(f, 0, 255)


def real_backgrounds(folder="real_empty"):
    return sorted((BENCH / folder).glob("*.jpg"))


def darken(rgba, rng):
    """무늬는 남기고 짙은 회색·검정으로 어둡게, 가끔 반사광"""
    rgb = rgba[:, :, :3].astype(np.float32)
    gray = rgb.mean(2, keepdims=True)
    rgb = gray * rng.uniform(0.6, 0.9) + rgb * rng.uniform(0.1, 0.4)
    rgb = rgb / max(1.0, float(np.percentile(gray, 95))) * rng.uniform(35, 95)
    if rng.random() < 0.4:
        h, w = rgb.shape[:2]
        yy, xx = np.mgrid[0:h, 0:w]
        cx, cy = rng.uniform(0, w), rng.uniform(0, h)
        rgb += np.exp(-((xx - cx) ** 2 + (yy - cy) ** 2) / (2 * (0.25 * max(h, w)) ** 2))[..., None] * rng.uniform(15, 45)
    return np.dstack([np.clip(rgb, 0, 255), rgba[:, :, 3:4]]).astype(np.uint8)


def camera(img, rng):
    """Pi4 카메라 모듈 흉내 — 화이트밸런스 · 비네팅 · 초점 흐림 · 센서 노이즈 · JPEG 압축"""
    f = img.astype(np.float32) * rng.uniform(0.92, 1.08, 3)
    xx, yy = np.meshgrid(np.linspace(-1, 1, W), np.linspace(-1, 1, H))
    f *= (1 - rng.uniform(0, 0.25) * (xx ** 2 + yy ** 2) / 2)[..., None]
    if rng.random() < 0.6:
        f = cv2.GaussianBlur(f, (0, 0), rng.uniform(0.5, 1.8))
    f += rng.normal(0, rng.uniform(1, 6), f.shape)
    ok, buf = cv2.imencode(".jpg", np.clip(f, 0, 255).astype(np.uint8), [cv2.IMWRITE_JPEG_QUALITY, int(rng.integers(55, 95))])
    return cv2.imdecode(buf, cv2.IMREAD_COLOR).astype(np.float32)


def place(rgba, scale, angle):
    h, w = rgba.shape[:2]
    rgba = cv2.resize(rgba, (max(4, int(w * scale)), max(4, int(h * scale))), interpolation=cv2.INTER_AREA)
    h, w = rgba.shape[:2]
    m = cv2.getRotationMatrix2D((w / 2, h / 2), angle, 1.0)
    c, s = abs(m[0, 0]), abs(m[0, 1])
    nw, nh = int(h * s + w * c), int(h * c + w * s)
    m[0, 2] += nw / 2 - w / 2
    m[1, 2] += nh / 2 - h / 2
    return cv2.warpAffine(rgba, m, (nw, nh), flags=cv2.INTER_LINEAR, borderValue=(0, 0, 0, 0))


def gap(a, b):
    """두 박스 사이 빈틈 (px). 겹치거나 맞닿으면 0"""
    dx = max(b[0] - (a[0] + a[2]), a[0] - (b[0] + b[2]), 0)
    dy = max(b[1] - (a[1] + a[3]), a[1] - (b[1] + b[3]), 0)
    return max(dx, dy)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("split")
    ap.add_argument("n", type=int)
    ap.add_argument("--sources", default="orig")
    ap.add_argument("--out", default="")
    ap.add_argument("--gen-bg", type=float, default=0.0)
    ap.add_argument("--empty", type=float, default=0.0)
    ap.add_argument("--camera", action="store_true")
    ap.add_argument("--distract", type=float, default=0.0)
    ap.add_argument("--real-bg", type=float, default=0.0)
    ap.add_argument("--real-bg-dir", default="real_empty")
    ap.add_argument("--stack", type=float, default=0.0)
    ap.add_argument("--dark", type=float, default=0.0)
    ap.add_argument("--frame", default="", help="장면 크기 WxH (탐지기가 보는 ROI 크기)")
    ap.add_argument("--px-per-cm", type=float, default=0.0)
    ap.add_argument("--seed", type=int, default=None, help="여러 개로 나눠 동시에 만들 때 조각마다 다르게")
    args = ap.parse_args()
    global W, H, PX_PER_CM
    if args.frame:
        W, H = (int(v) for v in args.frame.lower().split("x"))
    if args.px_per_cm:
        PX_PER_CM = args.px_per_cm
    print(f"장면 {W}×{H} · {PX_PER_CM} px/cm")
    gen_bgs = gen_backgrounds() if args.gen_bg > 0 else []
    if args.gen_bg > 0:
        print(f"생성 바탕 {len(gen_bgs)} 장 · 비율 {args.gen_bg}")
    split, n = args.split, args.n
    rng = np.random.default_rng(args.seed if args.seed is not None else (1 if split == "test" else 2) + 10 * len(args.out))
    cutouts = load_cutouts(split, args.sources.split(","))
    print(f"오린 물건 {len(cutouts)} 개 ({args.sources})")
    base = background()
    out_dir = BENCH / (f"scenes_{split}_{args.out}" if args.out else f"scenes_{split}")
    out_dir.mkdir(parents=True, exist_ok=True)
    coco = {"images": [], "annotations": [], "categories": [{"id": 0, "name": "item"}]}
    inner = (int(BAND * H) + 8, int(BAND * H) + 8, W - int(BAND * H) - 8, H - int(BAND * H) - 8)   # x0,y0,x1,y1
    aid = 0
    real_bgs = real_backgrounds(args.real_bg_dir)
    for i in range(n):
        if real_bgs and rng.random() < args.real_bg:
            canvas, kind = gen_panel(real_bgs[int(rng.integers(len(real_bgs)))], rng), "real"
        elif gen_bgs and rng.random() < args.gen_bg:
            canvas, kind = gen_panel(gen_bgs[int(rng.integers(len(gen_bgs)))], rng), "gen"
        else:
            canvas, kind = vary_panel(base, rng)
        if rng.random() < args.distract:
            canvas = distract(canvas, rng)
        px_per_cm = PX_PER_CM * (rng.uniform(0.65, 1.3) if args.camera else 1.0)
        shadow = np.zeros((H, W), np.float32)
        boxes, objs = [], []
        n_obj = 0 if rng.random() < args.empty else int(rng.integers(1, 9))
        for _ in range(n_obj):
            m = cutouts[int(rng.integers(len(cutouts)))]
            rgba = cv2.imread(str(BENCH / "cutouts" / m["file"]), cv2.IMREAD_UNCHANGED)
            long_cm = rng.uniform(*(m.get("size_cm") or SIZE_CM[m["group"]]))
            if "size_cm" in m:
                rgba = harmonize(rgba, float(canvas.mean()), rng)
            dark = rng.random() < args.dark
            if dark:
                rgba = darken(rgba, rng)
            obj = place(rgba, long_cm * px_per_cm / max(rgba.shape[:2]), rng.uniform(0, 360))
            oh, ow = obj.shape[:2]
            if ow >= inner[2] - inner[0] or oh >= inner[3] - inner[1]:
                continue
            stacked = bool(boxes) and rng.random() < args.stack
            for _try in range(30):
                if stacked:                               # 앞 물건 위에 포개기 — 겹침 검사 없이 그 물건에 걸치게
                    bx, by, bw, bh = boxes[int(rng.integers(len(boxes)))]
                    x = int(bx + bw / 2 - ow / 2 + rng.uniform(-0.55, 0.55) * (bw + ow) / 2)
                    y = int(by + bh / 2 - oh / 2 + rng.uniform(-0.55, 0.55) * (bh + oh) / 2)
                    if x < inner[0] or y < inner[1] or x + ow > inner[2] or y + oh > inner[3]:
                        continue
                    break
                if "size_cm" in m and rng.random() < 0.06:  # 판넬 밖으로 걸친 물건 (일부만 보임)
                    x = int(rng.choice([-ow // 3, W - 2 * ow // 3])) if rng.random() < 0.5 else int(rng.integers(0, W - ow))
                    y = int(rng.integers(0, H - oh)) if x < 0 or x > W - ow else int(rng.choice([-oh // 3, H - 2 * oh // 3]))
                    if not any(x < bx + bw and bx < x + ow and y < by + bh and by < y + oh for bx, by, bw, bh in boxes):
                        break
                    continue
                if boxes and rng.random() < 0.3:          # 앞 물건 옆에 붙여 놓기
                    bx, by, bw, bh = boxes[int(rng.integers(len(boxes)))]
                    x = int(bx + bw + rng.integers(-6, 12)) if rng.random() < 0.5 else int(bx - ow - rng.integers(-6, 12))
                    y = int(by + rng.integers(-oh // 2, max(1, bh // 2)))
                else:
                    x, y = int(rng.integers(inner[0], inner[2] - ow)), int(rng.integers(inner[1], inner[3] - oh))
                if x < inner[0] or y < inner[1] or x + ow > inner[2] or y + oh > inner[3]:
                    continue
                if any(x < bx + bw - 4 and bx < x + ow - 4 and y < by + bh - 4 and by < y + oh - 4 for bx, by, bw, bh in boxes):
                    continue                                 # 박스가 겹치지는 않게 (붙는 건 허용)
                break
            else:
                continue
            # 판 밖으로 나간 부분은 잘라 낸다
            x0, y0 = max(0, -x), max(0, -y)
            obj = obj[y0: H - y, x0: W - x]
            x, y = x + x0, y + y0
            oh, ow = obj.shape[:2]
            if (obj[:, :, 3] > 128).sum() < 400:
                continue
            a = obj[:, :, 3:4].astype(np.float32) / 255
            sx, sy = int(rng.integers(4, 14)), int(rng.integers(4, 14))     # 그림자 (오른쪽 아래로 번짐)
            sh = cv2.GaussianBlur(obj[:, :, 3].astype(np.float32) / 255, (0, 0), 7)
            ys, xs = slice(y + sy, min(H, y + sy + oh)), slice(x + sx, min(W, x + sx + ow))
            shadow[ys, xs] = np.maximum(shadow[ys, xs], sh[: ys.stop - ys.start, : xs.stop - xs.start] * rng.uniform(0.2, 0.45))
            objs.append((obj, a, x, y, m, x0 > 0 or y0 > 0 or x + ow >= W or y + oh >= H, stacked, dark))
            boxes.append((x, y, ow, oh))
        canvas *= (1 - shadow)[..., None]
        for obj, a, x, y, m, *_ in objs:
            region = canvas[y:y + obj.shape[0], x:x + obj.shape[1]]
            region[:] = region * (1 - a) + obj[:, :, :3].astype(np.float32) * a
        if args.camera:
            canvas = camera(canvas, rng)
        canvas = np.clip(canvas + rng.normal(0, 2.0, canvas.shape), 0, 255).astype(np.uint8)
        name = f"{split}_{i:04d}.jpg"
        cv2.imwrite(str(out_dir / name), canvas, [cv2.IMWRITE_JPEG_QUALITY, 92])
        coco["images"].append({"id": i, "file_name": name, "width": W, "height": H, "panel": kind})
        lab = cv2.cvtColor(canvas, cv2.COLOR_BGR2Lab)
        # 뒤에 붙인 물건이 앞 물건을 가린다 → 물건마다 보이는 부분만 남긴다
        covered = np.zeros((H, W), bool)
        visible = [None] * len(objs)
        for k in range(len(objs) - 1, -1, -1):
            obj, a, x, y = objs[k][:4]
            full = np.zeros((H, W), bool)
            full[y:y + obj.shape[0], x:x + obj.shape[1]] = a[:, :, 0] > 0.5
            visible[k] = (full & ~covered, int(full.sum()))
            covered |= full
        for k, ((obj, a, x, y, m, partial, stacked, dark), (bx, by, bw, bh)) in enumerate(zip(objs, boxes)):
            vis, total = visible[k]
            if total == 0 or vis.sum() < 0.25 * total:
                continue                                     # 거의 다 가려진 물건은 정답에서 뺀다
            alpha = vis[y:y + obj.shape[0], x:x + obj.shape[1]]
            ys, xs = np.nonzero(alpha)
            tight = [x + int(xs.min()), y + int(ys.min()), int(xs.max() - xs.min() + 1), int(ys.max() - ys.min() + 1)]
            obj_l = lab[y:y + obj.shape[0], x:x + obj.shape[1], 0][alpha].mean()
            ring = cv2.dilate(alpha.astype(np.uint8), np.ones((15, 15), np.uint8)) - alpha.astype(np.uint8)
            bg_l = lab[y:y + obj.shape[0], x:x + obj.shape[1], 0][ring > 0].mean() if ring.any() else obj_l
            touching = any(gap((bx, by, bw, bh), b) < 14 for b in boxes if b != (bx, by, bw, bh))
            coco["annotations"].append({"id": aid, "image_id": i, "category_id": 0, "bbox": tight, "area": tight[2] * tight[3],
                                        "iscrowd": 0, "group": m["group"], "contrast": round(float(abs(obj_l - bg_l)), 1),
                                        "touching": bool(touching), "partial": bool(partial), "stacked": bool(stacked),
                                        "occluded": round(1 - float(vis.sum()) / total, 2), "dark": bool(dark), "source": m["file"]})
            aid += 1
        if (i + 1) % 100 == 0:
            print(f"{i + 1} 장", flush=True)
    json.dump(coco, open(out_dir / "scenes.json", "w"), ensure_ascii=False)
    print(f"{split}: 장면 {n} · 물건 {aid} · 판 {dict(zip(*np.unique([im['panel'] for im in coco['images']], return_counts=True)))}")


if __name__ == "__main__":
    main()
