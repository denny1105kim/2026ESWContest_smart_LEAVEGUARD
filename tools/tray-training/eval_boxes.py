"""예측 박스를 트레이 장면 정답과 비교해 맞음·합쳐짐·쪼개짐·못 찾음·잘못 잡음을 센다.

예측: *.json {"파일": [[x, y, w, h, score], ...]} 또는 *.jsonl (tray-node offline 출력). 여러 개면 합친다.
맞음 = 정답과 IoU ≥ 0.5 (1:1), 잘못 잡음 = 모든 정답과 IoU < 0.1
usage: python tools/tray-training/eval_boxes.py <이름> <예측>... [--split test] [--score 0.0]
"""
import argparse
import collections
import json
from pathlib import Path

BENCH = Path(__file__).resolve().parents[2] / "research" / "tray_bench"


def iou(a, b):
    ix = max(0, min(a[0] + a[2], b[0] + b[2]) - max(a[0], b[0]))
    iy = max(0, min(a[1] + a[3], b[1] + b[3]) - max(a[1], b[1]))
    inter = ix * iy
    return inter / (a[2] * a[3] + b[2] * b[3] - inter + 1e-9)


def cover(gt, p):
    """정답 박스 중 예측이 덮는 비율"""
    ix = max(0, min(gt[0] + gt[2], p[0] + p[2]) - max(gt[0], p[0]))
    iy = max(0, min(gt[1] + gt[3], p[1] + p[3]) - max(gt[1], p[1]))
    return ix * iy / (gt[2] * gt[3] + 1e-9)


def load_preds(paths, score):
    preds, invalid = collections.defaultdict(list), {}
    for path in paths:
        path = Path(path)
        if path.suffix == ".jsonl":
            for line in open(path):
                d = json.loads(line)
                name = Path(d["captured_at"]).name           # offline 은 captured_at 에 파일 이름을 넣는다
                q = d["scene_quality"]
                if not q["valid"]:
                    invalid[name] = q["reason"]
                preds[name] += [c["bbox"] + [1.0] for c in d["candidates"]]
        else:
            for name, boxes in json.load(open(path)).items():
                preds[name] += [b for b in boxes if b[4] >= score]
    # 여러 출처를 합칠 때 같은 물건 겹침 제거 (점수 높은 것 · 먼저 온 것 우선)
    for name, boxes in preds.items():
        boxes.sort(key=lambda b: -b[4])
        kept = []
        for b in boxes:
            if all(iou(b, k) < 0.5 for k in kept):
                kept.append(b)
        preds[name] = kept
    return preds, invalid


def bucket(a):
    c = a["contrast"]
    s = (a["bbox"][2] * a["bbox"][3]) ** 0.5
    return {"contrast": "낮음 <25" if c < 25 else "중간 25-60" if c < 60 else "높음 ≥60",
            "size": "작음 <150px" if s < 150 else "중간 150-300" if s < 300 else "큼 ≥300",
            "touching": "붙음" if a["touching"] else "떨어짐", "group": a["group"]}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("name")
    ap.add_argument("preds", nargs="+")
    ap.add_argument("--split", default="test")
    ap.add_argument("--score", type=float, default=0.0)
    args = ap.parse_args()
    gt = json.load(open(BENCH / f"scenes_{args.split}" / "scenes.json"))
    images = {im["id"]: im for im in gt["images"]}
    by_image = {im["id"]: [] for im in gt["images"]}     # 물건 없는 장면도 센다 (거기서 잡은 박스는 전부 잘못 잡음)
    for a in gt["annotations"]:
        by_image[a["image_id"]].append(a)
    preds, invalid = load_preds(args.preds, args.score)

    outcome = collections.Counter()
    fails = collections.Counter()
    table = collections.defaultdict(lambda: collections.Counter())
    n_pred = n_fp = 0
    for iid, anns in by_image.items():
        im = images[iid]
        name = im["file_name"]
        boxes = preds.get(name, [])
        n_pred += len(boxes)
        used = set()
        pairs = sorted(((iou(a["bbox"], b), ai, bi) for ai, a in enumerate(anns) for bi, b in enumerate(boxes)), reverse=True)
        matched = {}
        for v, ai, bi in pairs:
            if v < 0.5:
                break
            if ai in matched or bi in used:
                continue
            matched[ai] = bi
            used.add(bi)
        for bi, b in enumerate(boxes):
            if bi not in used and all(iou(a["bbox"], b) < 0.1 for a in anns):
                n_fp += 1
        for ai, a in enumerate(anns):
            if ai in matched:
                kind = "맞음"
            elif name in invalid:
                kind = f"장면 무효({invalid[name]})"
            elif any(sum(cover(o["bbox"], b) > 0.5 for o in anns) >= 2 and cover(a["bbox"], b) > 0.5 for b in boxes):
                kind = "합쳐짐"
            elif any(cover(a["bbox"], b) > 0.5 for b in boxes):
                kind = "쪼개짐·박스 어긋남"
            else:
                kind = "못 찾음"
            outcome[kind] += 1
            ok = kind == "맞음"
            for k, v in list(bucket(a).items()) + [("panel", im["panel"])]:
                table[(k, v)]["n"] += 1
                table[(k, v)]["ok"] += ok
            if not ok:
                fails[(a["group"], kind)] += 1

    total = max(1, sum(outcome.values()))
    print(f"== {args.name}  (장면 {len(by_image)} · 물건 {total} · 예측 {n_pred})")
    print(f"찾음(recall) {outcome['맞음'] / total:.1%} · 잘못 잡은 박스 {n_fp} (장면당 {n_fp / len(by_image):.2f}) · "
          f"정밀도 {(n_pred - n_fp) / max(1, n_pred):.1%} · 무효 장면 {len(invalid)}")
    for k, v in outcome.most_common():
        print(f"   {k:<28} {v:4d}  {v / total:.1%}")
    for key in ("panel", "contrast", "size", "touching"):
        row = " · ".join(f"{v} {c['ok'] / c['n']:.0%}({c['n']})" for (k, v), c in sorted(table.items()) if k == key)
        print(f"   [{key}] {row}")
    worst = sorted(((c["ok"] / c["n"], v, c["n"]) for (k, v), c in table.items() if k == "group" and c["n"] >= 10))[:6]
    print("   [약한 그룹] " + " · ".join(f"{v} {r:.0%}({n})" for r, v, n in worst))
    json.dump({"name": args.name, "recall": outcome["맞음"] / total, "fp": n_fp, "pred": n_pred, "invalid": len(invalid),
               "outcome": dict(outcome), "table": {f"{k}:{v}": dict(c) for (k, v), c in table.items()}},
              open(BENCH / "pred" / f"metrics_{args.name}.json", "w"), ensure_ascii=False, indent=1)


if __name__ == "__main__":
    main()
