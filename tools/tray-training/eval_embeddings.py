"""물건 재식별 평가 (CORe50, CC BY 4.0): 세션 s1 에 등록, 나머지 세션에서 다시 찾기 + 모르는 물건(o5, o10, …) 거절.
특징 모델은 보드와 같은 ONNX (models/tray), 전처리는 늘려 맞춤 · RGB · ImageNet.

준비: research/core50/core50_128x128/
usage: python tools/tray-training/eval_embeddings.py
"""
import json
from pathlib import Path

import cv2
import numpy as np
import onnxruntime as ort

ROOT = Path(__file__).resolve().parents[2]
CORE = ROOT / "research" / "core50" / "core50_128x128"
MODELS = ROOT / "models" / "tray"
OUT = ROOT / "research" / "tray_bench" / "pred"
KINDS = ["어댑터", "휴대폰", "가위", "전구", "캔", "안경", "공", "마커", "컵", "리모컨"]
ENCODERS = {"ORBIT": ("orbit_protonets_effb0_224.onnx", 224), "DINOv2": ("dinov2_vits14_reg_168.onnx", 168)}


def kind_of(obj):
    return KINDS[(obj - 1) // 5]


def frames(session, obj, n):
    files = sorted((CORE / f"s{session}" / f"o{obj}").glob("*.png"))
    return [files[i] for i in np.linspace(0, len(files) - 1, n).astype(int)]


def encode(sess, size, path):
    img = cv2.imread(str(path))
    x = cv2.resize(img, (size, size), interpolation=cv2.INTER_LINEAR)[:, :, ::-1].astype(np.float32) / 255
    x = (x - [0.485, 0.456, 0.406]) / [0.229, 0.224, 0.225]
    return sess.run(None, {"input": x.transpose(2, 0, 1)[None].astype(np.float32)})[0].reshape(-1)


def unit(v):
    return v / np.linalg.norm(v, axis=-1, keepdims=True)


def main():
    known = [o for o in range(1, 51) if o % 5 != 0]
    unknown = [o for o in range(1, 51) if o % 5 == 0]
    report = {}
    for name, (file, size) in ENCODERS.items():
        sess = ort.InferenceSession(str(MODELS / file), providers=["CPUExecutionProvider"])
        gallery = {o: np.stack([encode(sess, size, p) for p in frames(1, o, 5)]) for o in known}
        queries = [(o, s, encode(sess, size, p)) for o in known + unknown for s in range(2, 12) for p in frames(s, o, 10)]
        q_obj = np.array([o for o, _, _ in queries])
        q_ses = np.array([s for _, s, _ in queries])
        Q = np.stack([v for _, _, v in queries])
        ids = np.array(known)
        G = {"갤러리 최댓값 cosine": lambda: np.stack([(unit(Q) @ unit(gallery[o]).T).max(1) for o in known], 1),
             "평균 프로토타입 cosine": lambda: unit(Q) @ unit(np.stack([unit(gallery[o]).mean(0) for o in known])).T,
             "ProtoNet 유클리드": lambda: -np.linalg.norm(Q[:, None] - np.stack([gallery[o].mean(0) for o in known])[None], axis=2)}
        for mname, fn in G.items():
            S = fn()                                          # 조회 × 등록 물건 점수 (클수록 가깝다)
            order = np.argsort(-S, 1)
            best = S[np.arange(len(S)), order[:, 0]]
            pred = ids[order[:, 0]]
            is_known = np.isin(q_obj, known)
            top1 = (pred == q_obj)[is_known].mean()
            wrong = is_known & (pred != q_obj)
            same_kind = np.mean([kind_of(p) == kind_of(o) for p, o in zip(pred[wrong], q_obj[wrong])]) if wrong.any() else 0
            # 모르는 물건을 5% 만 받아들이는 기준에서, 아는 물건을 맞게 받아들이는 비율
            thr = np.quantile(best[~is_known], 0.95)
            tpr = ((best >= thr) & (pred == q_obj))[is_known].mean()
            by_kind = {k: float((pred == q_obj)[is_known & (np.array([kind_of(o) for o in q_obj]) == k)].mean()) for k in KINDS}
            by_ses = {int(s): float((pred == q_obj)[is_known & (q_ses == s)].mean()) for s in range(2, 12)}
            key = f"{name} · {mname}"
            report[key] = {"top1": float(top1), "오답 중 같은 종류": float(same_kind), "모르는물건5%기준_정답수락": float(tpr),
                           "종류별": by_kind, "세션별": by_ses}
            weak = sorted(by_kind.items(), key=lambda kv: kv[1])[:3]
            print(f"{key:<32} top1 {top1:.1%} · 오답 중 같은 종류 {same_kind:.0%} · 모르는 물건 5% 수락 기준 정답 수락 {tpr:.1%} · "
                  f"약한 종류 {', '.join(f'{k} {v:.0%}' for k, v in weak)} · 세션 최저 {min(by_ses.values()):.0%}")
    json.dump(report, open(OUT / "embeddings_core50.json", "w"), ensure_ascii=False, indent=1)


if __name__ == "__main__":
    main()
