"""YOLOX-Nano 미세조정. 공식 YOLOX(vendor/YOLOX)의 모델·손실·증강만 쓰고 학습 루프는 직접 돈다.

usage: python tools/tray-training/train_yolox.py [에폭 40] [학습세트 폴더 trainset] [입력 크기 416]
  입력 크기는 보드 설정 detector.input 과 같게 (트레이 모델은 512). YOLOX_INIT=<best.pth> 로 이어 학습
"""
import json
import os
import sys
import time
from pathlib import Path

import cv2
import numpy as np
import torch
from torch.utils.data import DataLoader, Dataset

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "vendor" / "YOLOX"))
from yolox.data.data_augment import TrainTransform, preproc          # noqa: E402
from yolox.models import YOLOX, YOLOPAFPN, YOLOXHead                  # noqa: E402
from yolox.utils import ModelEMA, postprocess                         # noqa: E402

PRETRAINED = Path(os.environ.get("YOLOX_INIT", ROOT / "weights" / "yolox_nano.pth"))

INPUT = (416, 416)
EPOCHS, TRAINSET = 40, ROOT / "trainset"
if __name__ == "__main__":          # 다른 스크립트가 import 할 때는 기본값을 쓴다
    EPOCHS = int(sys.argv[1]) if len(sys.argv) > 1 else EPOCHS
    TRAINSET = ROOT / (sys.argv[2] if len(sys.argv) > 2 else TRAINSET.name)
    if len(sys.argv) > 3:
        INPUT = (int(sys.argv[3]), int(sys.argv[3]))
RUN = ROOT / "runs" / f"yolox_nano_{TRAINSET.name}"
BATCH = 32
BASE_LR = 0.01 / 64 * BATCH      # YOLOX 기본값을 배치 크기에 맞춰 조정
WARMUP_EPOCHS = 2
NO_AUG_LAST = 5                  # 마지막 몇 에폭은 증강을 끈다 (YOLOX 방식)
WORKERS = 8


class Items(Dataset):
    """COCO json. file_name 은 저장소 루트 기준 상대경로"""

    def __init__(self, json_path, train):
        data = json.loads(Path(json_path).read_text(encoding="utf-8"))
        self.categories = sorted(data["categories"], key=lambda c: c["id"])
        index_of = {c["id"]: i for i, c in enumerate(self.categories)}

        by_image = {}
        for a in data["annotations"]:
            x, y, w, h = a["bbox"]
            by_image.setdefault(a["image_id"], []).append([x, y, x + w, y + h, index_of[a["category_id"]]])
        # 물건 없는 장면도 넣어 아무것도 잡지 않는 법을 배운다
        self.records = [(im["file_name"], np.array(by_image.get(im["id"], np.zeros((0, 5))), dtype=np.float32).reshape(-1, 5), im["id"])
                        for im in data["images"]]
        self.train = train
        self.transform = TrainTransform(max_labels=50)

    def __len__(self):
        return len(self.records)

    def __getitem__(self, i):
        rel, targets, image_id = self.records[i]
        img = cv2.imread(str(ROOT / rel))
        if img is None:                      # 깨진 파일은 빈 이미지로 넘긴다
            return np.zeros((3, *INPUT), np.float32), np.zeros((50, 5), np.float32)
        if self.train:
            img, labels = self.transform(img, targets.copy(), INPUT)
            return img, labels
        padded, ratio = preproc(img, INPUT)
        return padded, np.float32(ratio), image_id


def build_model(num_classes):
    backbone = YOLOPAFPN(0.33, 0.25, in_channels=[256, 512, 1024], act="silu", depthwise=True)
    head = YOLOXHead(num_classes, 0.25, in_channels=[256, 512, 1024], act="silu", depthwise=True)
    model = YOLOX(backbone, head)
    for m in model.modules():
        if isinstance(m, torch.nn.BatchNorm2d):
            m.eps, m.momentum = 1e-3, 0.03

    state = torch.load(PRETRAINED, map_location="cpu", weights_only=False)["model"]
    # 클래스 수가 다르면(COCO 80 → 1) 분류층만 빼고 얹는다
    own = model.state_dict()
    state = {k: v for k, v in state.items() if "cls_preds" not in k or (k in own and own[k].shape == v.shape)}
    missing, unexpected = model.load_state_dict(state, strict=False)
    print(f"시작 가중치 적용 — 새로 배우는 층 {len(missing)}개, 버린 층 {len(unexpected)}개")
    return model


def lr_at(epoch, step, steps_per_epoch):
    """2에폭 warmup 후 코사인 감소, 마지막은 최소 lr 유지"""
    progress = epoch + step / steps_per_epoch
    if progress < WARMUP_EPOCHS:
        return BASE_LR * (progress / WARMUP_EPOCHS) ** 2
    last = EPOCHS - NO_AUG_LAST
    if progress >= last:
        return BASE_LR * 0.05
    t = (progress - WARMUP_EPOCHS) / (last - WARMUP_EPOCHS)
    return BASE_LR * (0.05 + 0.95 * 0.5 * (1 + np.cos(np.pi * t)))


@torch.no_grad()
def evaluate(model, dataset, categories):
    """검증 세트 mAP (pycocotools)"""
    from pycocotools.coco import COCO
    from pycocotools.cocoeval import COCOeval

    model.eval()
    loader = DataLoader(dataset, batch_size=16, num_workers=WORKERS, collate_fn=lambda b: b)
    results = []
    for batch in loader:
        imgs = torch.from_numpy(np.stack([b[0] for b in batch])).cuda()
        with torch.autocast("cuda", torch.float16):
            outputs = model(imgs)
        outputs = postprocess(outputs.float(), len(categories), conf_thre=0.01, nms_thre=0.65)
        for (_, ratio, image_id), out in zip(batch, outputs):
            if out is None:
                continue
            boxes = out[:, :4].cpu().numpy() / ratio
            scores = (out[:, 4] * out[:, 5]).cpu().numpy()
            classes = out[:, 6].cpu().numpy().astype(int)
            for (x1, y1, x2, y2), score, cls in zip(boxes, scores, classes):
                results.append({"image_id": int(image_id), "category_id": categories[cls]["id"],
                                "bbox": [float(x1), float(y1), float(x2 - x1), float(y2 - y1)],
                                "score": float(score)})
    if not results:
        return 0.0, 0.0

    coco = COCO(str(TRAINSET / "val.json"))
    stats = COCOeval(coco, coco.loadRes(results), "bbox")
    stats.evaluate(); stats.accumulate(); stats.summarize()
    return stats.stats[0], stats.stats[1]        # mAP50-95, mAP50


def main():
    RUN.mkdir(parents=True, exist_ok=True)
    train_set = Items(TRAINSET / "train.json", train=True)
    val_set = Items(TRAINSET / "val.json", train=False)
    categories = train_set.categories
    print(f"학습 {len(train_set)}장 / 검증 {len(val_set)}장 / 분류 {len(categories)}개")

    model = build_model(len(categories)).cuda()
    ema = ModelEMA(model, decay=0.9998)

    # BN 과 bias 에는 weight decay 를 걸지 않는다 (YOLOX 기본)
    decay, no_decay = [], []
    for name, p in model.named_parameters():
        (no_decay if p.ndim == 1 else decay).append(p)
    optimizer = torch.optim.SGD([{"params": decay, "weight_decay": 5e-4},
                                 {"params": no_decay, "weight_decay": 0.0}],
                                lr=BASE_LR, momentum=0.9, nesterov=True)
    scaler = torch.amp.GradScaler("cuda")

    best = 0.0
    for epoch in range(EPOCHS):
        if epoch == EPOCHS - NO_AUG_LAST:
            train_set.transform = TrainTransform(max_labels=50, flip_prob=0.0, hsv_prob=0.0)
            model.head.use_l1 = True          # 마지막 구간에 L1 손실 추가 (YOLOX 방식)
            print("증강 끄고 L1 손실 추가")

        loader = DataLoader(train_set, batch_size=BATCH, shuffle=True, num_workers=WORKERS,
                           drop_last=True, pin_memory=True, persistent_workers=False)
        model.train()
        started, running = time.time(), 0.0
        for step, (imgs, labels) in enumerate(loader):
            for group in optimizer.param_groups:
                group["lr"] = lr_at(epoch, step, len(loader))
            imgs = imgs.cuda(non_blocking=True).float()
            labels = labels.cuda(non_blocking=True).float()

            with torch.autocast("cuda", torch.float16):
                losses = model(imgs, labels)
            optimizer.zero_grad(set_to_none=True)
            scaler.scale(losses["total_loss"]).backward()
            scaler.step(optimizer)
            scaler.update()
            ema.update(model)
            running += losses["total_loss"].item()

        print(f"[{epoch + 1:3d}/{EPOCHS}] loss {running / len(loader):.3f} "
              f"lr {optimizer.param_groups[0]['lr']:.5f} {time.time() - started:.0f}초", flush=True)

        if (epoch + 1) % 5 == 0 or epoch == EPOCHS - 1:
            mAP, mAP50 = evaluate(ema.ema, val_set, categories)
            print(f"  검증 mAP50-95 {mAP:.3f} / mAP50 {mAP50:.3f}", flush=True)
            if mAP > best:
                best = mAP
                torch.save({"model": ema.ema.state_dict(), "epoch": epoch, "mAP": mAP,
                            "categories": categories}, RUN / "best.pth")
                print(f"  저장 — 지금까지 가장 좋음", flush=True)

    print(f"\n끝. 가장 좋은 mAP50-95 {best:.3f} → {RUN / 'best.pth'}")


if __name__ == "__main__":
    main()
