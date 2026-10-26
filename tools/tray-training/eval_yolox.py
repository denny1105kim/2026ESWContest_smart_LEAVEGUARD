"""체크포인트를 다른 학습 세트의 val.json 으로 평가한다 (mAP).

usage: python tools/tray-training/eval_yolox.py <체크포인트.pth> <학습세트 폴더>
"""
import contextlib
import io
import json
import sys
from pathlib import Path

import numpy as np
import torch
from torch.utils.data import DataLoader

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(ROOT / "vendor" / "YOLOX"))
import train_yolox as T                                     # noqa: E402
from pycocotools.coco import COCO                            # noqa: E402
from pycocotools.cocoeval import COCOeval                    # noqa: E402
from yolox.utils import postprocess                          # noqa: E402


def main():
    ckpt_path, trainset = Path(sys.argv[1]), ROOT / sys.argv[2]
    ckpt = torch.load(ckpt_path, map_location="cpu", weights_only=False)
    categories = ckpt["categories"]

    model = T.build_model(len(categories))
    model.load_state_dict(ckpt["model"])
    model = model.cuda().eval()

    T.TRAINSET = trainset
    dataset = T.Items(trainset / "val.json", train=False)

    results = []
    with torch.no_grad():
        for batch in DataLoader(dataset, batch_size=16, num_workers=T.WORKERS, collate_fn=lambda b: b):
            imgs = torch.from_numpy(np.stack([b[0] for b in batch])).cuda()
            with torch.autocast("cuda", torch.float16):
                outputs = model(imgs)
            for (_, ratio, image_id), out in zip(batch, postprocess(outputs.float(), len(categories), 0.01, 0.65)):
                if out is None:
                    continue
                boxes = out[:, :4].cpu().numpy() / ratio
                scores = (out[:, 4] * out[:, 5]).cpu().numpy()
                classes = out[:, 6].cpu().numpy().astype(int)
                for (x1, y1, x2, y2), score, cls in zip(boxes, scores, classes):
                    results.append({"image_id": int(image_id), "category_id": categories[cls]["id"],
                                    "bbox": [float(x1), float(y1), float(x2 - x1), float(y2 - y1)],
                                    "score": float(score)})

    coco = COCO()
    coco.dataset = json.loads((trainset / "val.json").read_text(encoding="utf-8"))
    with contextlib.redirect_stdout(io.StringIO()):
        coco.createIndex()
        e = COCOeval(coco, coco.loadRes(results), "bbox")
        e.evaluate(); e.accumulate(); e.summarize()
    print(f"{ckpt_path.parent.name} → {trainset.name}: "
          f"mAP50-95 {e.stats[0]:.3f}  mAP50 {e.stats[1]:.3f}  (검증 {len(dataset)}장)")


if __name__ == "__main__":
    main()
