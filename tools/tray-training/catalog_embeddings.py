"""오린 물건 카탈로그 → 월패드 "혹시 지갑?" 제안용 종류별 대표 벡터 (wallpad assets/item_catalog.json).
전처리·공간 ID 는 tray-node/src/Encoder.h 와 같아야 한다 (ID 가 다르면 월패드가 제안하지 않는다).
--bg-dir 에 실제 빈 판 사진을 주면 바탕에 쓴다 (단색 회색 바탕은 실제 크롭과 잘 안 맞았다).

usage: python tools/tray-training/catalog_embeddings.py <preset> <model.onnx> <출력 json> [--fuse preset2 model2.onnx] [--bg-dir 폴더]
         [--per-group 8] [--sample 120] [--min-score 0.33]
"""
import argparse
import hashlib
import json
import random
from pathlib import Path

import numpy as np
import onnxruntime as ort
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
CUTOUTS = ROOT / "research" / "tray_bench" / "cutouts"
PAD = 0.12                         # 노드가 박스를 사방 12% 넓혀 자른다
PRESETS = {  # 이름 → (입력 한 변, 차원, 출력 이름, L2)
    "orbit_protonets_effb0_224": (224, 1280, "gap", False),
    "dinov2_vits14_reg_168": (168, 384, "cls", True),
}

# 카탈로그 group → 월패드에 보일 이름 · 아이콘. misc 는 제안하지 않는다
NAMES = {
    "phone": ("휴대폰", "phone"),
    "wallet": ("지갑", "wallet"),
    "key": ("열쇠", "key"),
    "card": ("카드 · 사원증", "badge"),
    "audio": ("이어폰", "headphones"),
    "watch": ("시계", "watch"),
    "eyewear": ("안경", "eyewear"),
    "toiletry": ("화장품", "toiletry"),
    "tissue": ("휴지", "tissue"),
    "charger": ("충전기", "charger"),
    "bottle": ("텀블러", "bottle"),
}


def space_id(preset: str, model: Path, fuse=None) -> str:
    size, _, out, l2 = PRESETS[preset]
    h = hashlib.sha256(model.read_bytes()).hexdigest()[:16]
    if fuse:
        h2 = hashlib.sha256(Path(fuse[1]).read_bytes()).hexdigest()[:16]
        return f"{preset}@{h}+{fuse[0]}@{h2}/rgb-sq0-imagenet/pad{int(round(PAD * 100))}/concat-l2/f32"
    return f"{preset}@{h}/rgb-sq0-resize{size}-imagenet/pad{int(round(PAD * 100))}/{out}{'-l2' if l2 else ''}/f32"


def background(boards: list, w: int, h: int, rng: random.Random) -> Image.Image:
    """w×h 바탕: 빈 판 사진이 있으면 그중 하나를 1~1.6배로 키워 아무 곳이나 자른다, 없으면 어두운 회색"""
    if not boards:
        return Image.new("RGB", (w, h), (72, 74, 80))
    b = rng.choice(boards)
    s = max(w / b.width, h / b.height) * rng.uniform(1.0, 1.6)
    b = b.resize((int(b.width * s) + 1, int(b.height * s) + 1))
    x, y = rng.randint(0, b.width - w), rng.randint(0, b.height - h)
    return b.crop((x, y, x + w, y + h))


def prepare(path: Path, sizes: list, boards: list, rng: random.Random) -> list:
    """오린 그림(RGBA)을 바탕에 12% 여백으로 올리고, 노드처럼 검은색으로 채워 정사각형으로 만든 뒤 size×size 로 줄인다"""
    im = Image.open(path).convert("RGBA")
    w, h = im.size
    dx, dy = round(w * PAD), round(h * PAD)
    bg = background(boards, w + 2 * dx, h + 2 * dy, rng)
    bg.paste(im, (dx, dy), im)
    side = max(bg.size)
    sq = Image.new("RGB", (side, side), (0, 0, 0))
    sq.paste(bg, ((side - bg.width) // 2, (side - bg.height) // 2))
    out = []
    for size in sizes:   # 같은 바탕 위 같은 그림을 모델마다의 크기로
        x = np.asarray(sq.resize((size, size), Image.BILINEAR), dtype=np.float32) / 255
        x = (x - [0.485, 0.456, 0.406]) / [0.229, 0.224, 0.225]
        out.append(x.transpose(2, 0, 1)[None].astype(np.float32))
    return out


def kmeans(X: np.ndarray, k: int, iters: int = 30, seed: int = 0) -> np.ndarray:
    """단위 벡터들을 k 개 대표로 (코사인 = 내적). 작은 데이터라 numpy 로 충분하다"""
    rng = np.random.default_rng(seed)
    k = min(k, len(X))
    C = X[rng.choice(len(X), k, replace=False)].copy()
    for _ in range(iters):
        a = (X @ C.T).argmax(1)
        for j in range(k):
            m = X[a == j]
            if len(m):
                C[j] = m.mean(0)
        C /= np.linalg.norm(C, axis=1, keepdims=True)
    return C


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("preset", choices=PRESETS)
    ap.add_argument("model")
    ap.add_argument("out")
    ap.add_argument("--fuse", nargs=2, metavar=("PRESET2", "MODEL2"), help="두 번째 모델 (노드 encoder2)")
    ap.add_argument("--min-score", type=float, default=0.33, help="월패드가 제안할 최저 점수 (파일에 적는다)")
    ap.add_argument("--bg-dir", help="빈 트레이 판 사진 폴더 (없으면 회색 바탕)")
    ap.add_argument("--per-group", type=int, default=8, help="종류마다 남길 대표 벡터 수")
    ap.add_argument("--sample", type=int, default=120, help="종류마다 특징을 뽑을 그림 수 (gen_lumina · abo 우선)")
    args = ap.parse_args()

    model = Path(args.model)
    size, dim, _, _ = PRESETS[args.preset]
    sess = ort.InferenceSession(str(model), providers=["CPUExecutionProvider"])
    sess2 = ort.InferenceSession(args.fuse[1], providers=["CPUExecutionProvider"]) if args.fuse else None
    size2, dim2 = (PRESETS[args.fuse[0]][0], PRESETS[args.fuse[0]][1]) if args.fuse else (None, 0)
    meta = json.load(open(CUTOUTS / "cutouts.json"))
    rng = random.Random(0)
    boards = [Image.open(p).convert("RGB") for p in sorted(Path(args.bg_dir).glob("*.jpg"))] if args.bg_dir else []
    print(f"바탕: {'빈 판 사진 ' + str(len(boards)) + '장' if boards else '회색'}")
    protos = []
    for group, (name, icon) in NAMES.items():
        files = [c["file"] for c in meta if c["group"] == group and c["file"].startswith(("gen_lumina/", "abo/"))]
        if len(files) < 20:
            files = [c["file"] for c in meta if c["group"] == group]
        rng.shuffle(files)
        vecs = []
        for f in files[: args.sample]:
            p = CUTOUTS / f
            if not p.exists():
                continue
            xs = prepare(p, [size] + ([size2] if sess2 else []), boards, rng)
            v = sess.run(None, {"input": xs[0]})[0].reshape(-1)
            if v.shape[0] != dim:
                raise SystemExit(f"출력 {v.shape[0]}차원 — 프리셋 {args.preset} 과 다른 모델")
            if sess2:
                v2 = sess2.run(None, {"input": xs[1]})[0].reshape(-1)
                v = np.concatenate([v / np.linalg.norm(v), v2 / np.linalg.norm(v2)])
            n = np.linalg.norm(v)
            if n > 1e-6:
                vecs.append(v / n)
        if not vecs:
            print(f"{group}: 그림 없음")
            continue
        C = kmeans(np.stack(vecs), args.per_group)
        for c in C:
            protos.append({"name": name, "icon": icon, "v": [round(float(x), 5) for x in c]})
        print(f"{group:9s} {name:8s} 그림 {len(vecs):3d} → 대표 {len(C)}")

    out = {"space_id": space_id(args.preset, model, args.fuse), "dim": dim + dim2, "min_score": args.min_score, "prototypes": protos}
    Path(args.out).write_text(json.dumps(out, ensure_ascii=False, separators=(",", ":")))
    print(f"저장 {args.out} · 대표 {len(protos)}개 · space {out['space_id']}")


if __name__ == "__main__":
    main()
