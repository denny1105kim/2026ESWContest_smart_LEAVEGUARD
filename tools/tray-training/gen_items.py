"""생성 모델로 단색 바탕 위 소지품 사진을 만든다 (gen_cutouts.py 로 오려 장면 재료로 쓴다).

usage: python tools/tray-training/gen_items.py <qwen|lumina> [변형당 장수] [--set 1|2] [--only 품목] [--size 768] [--steps N]
출력: research/tray_bench/gen/<모델>/*.png + gen.jsonl. 이미 있는 파일은 건너뛴다.
"""
import argparse
import json
import time
import zlib
from pathlib import Path

import torch

from item_catalog import BACKGROUNDS, ITEMS, ITEMS_2, prompt

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "research" / "tray_bench" / "gen"
NEG = "hand, person, multiple objects, cropped, cut off, text, watermark, logo, blurry, drawing, illustration, 3d render"


def load(model):
    if model == "qwen":
        from diffusers import DiffusionPipeline, PipelineQuantizationConfig
        q = PipelineQuantizationConfig(quant_backend="bitsandbytes_4bit",
                                       quant_kwargs={"load_in_4bit": True, "bnb_4bit_quant_type": "nf4",
                                                     "bnb_4bit_compute_dtype": torch.bfloat16},
                                       components_to_quantize=["transformer", "text_encoder"])
        pipe = DiffusionPipeline.from_pretrained("Qwen/Qwen-Image", torch_dtype=torch.bfloat16, quantization_config=q)
        pipe.enable_model_cpu_offload()   # 16GB GPU 에 맞추려고 4bit + CPU 오프로드
        return pipe, 30
    from diffusers import Lumina2Pipeline
    pipe = Lumina2Pipeline.from_pretrained("Alpha-VLLM/Lumina-Image-2.0", torch_dtype=torch.bfloat16).to("cuda")
    return pipe, 30


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("model", choices=["qwen", "lumina"])
    ap.add_argument("per_variant", type=int, nargs="?")
    ap.add_argument("--set", type=int, default=1, choices=[1, 2])
    ap.add_argument("--only", default="")
    ap.add_argument("--size", type=int, default=768)
    ap.add_argument("--steps", type=int)
    args = ap.parse_args()
    out = OUT / args.model
    out.mkdir(parents=True, exist_ok=True)
    jobs = []
    catalog = [(*it, 15) for it in ITEMS] if args.set == 1 else ITEMS_2
    for group, noun, variants, size_cm, n in catalog:
        if args.only and args.only not in noun:
            continue
        for variant in variants:
            for k in range(args.per_variant or n):
                jobs.append((group, noun, variant, size_cm, k))
    pipe, steps = load(args.model)
    pipe.set_progress_bar_config(disable=True)
    steps = args.steps or steps
    log = open(out / "gen.jsonl", "a")
    t0 = time.time()
    done = 0
    for group, noun, variant, size_cm, k in jobs:
        key = f"{noun}|{variant}" + ("|2" if args.set == 2 else "")
        seed = zlib.crc32(key.encode()) % 10**6 * 1000 + k   # 품목·변형마다 고정
        name = f"{group}_{seed}.png"
        if (out / name).exists():
            continue
        bg = BACKGROUNDS[(seed // 7) % len(BACKGROUNDS)]
        p = prompt(noun, variant, bg)
        g = torch.Generator("cpu").manual_seed(seed)
        if args.model == "qwen":
            img = pipe(prompt=p, negative_prompt=NEG, true_cfg_scale=4.0, num_inference_steps=steps,
                       width=args.size, height=args.size, generator=g).images[0]
        else:
            img = pipe(prompt=p, negative_prompt=NEG, guidance_scale=4.0, num_inference_steps=steps,
                       width=args.size, height=args.size, generator=g).images[0]
        img.save(out / name)
        log.write(json.dumps({"file": name, "group": group, "noun": noun, "variant": variant, "size_cm": size_cm,
                              "seed": seed, "prompt": p}, ensure_ascii=False) + "\n")
        log.flush()
        done += 1
        if done % 10 == 0 or done == 1:
            print(f"{done}/{len(jobs)} · {(time.time() - t0) / done:.1f} s/장", flush=True)
    print(f"끝 {done} 장")


if __name__ == "__main__":
    main()
