"""빈 트레이·책상 바탕을 Lumina-Image-2.0 으로 생성한다 (정답 없는 배경, 얼룩·반사를 "물건 아님"으로 배우게).

usage: python tools/tray-training/gen_backgrounds.py <장수>
출력: research/tray_bench/backgrounds/gen_*.jpg + backgrounds.jsonl
"""
import json
import sys
import time
from pathlib import Path

import numpy as np
import torch

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "research" / "tray_bench" / "backgrounds"

SURFACES = [
    "matte black plastic surface", "dark charcoal gray plastic surface", "medium gray plastic surface", "light gray plastic surface",
    "close-up of the flat bottom of a matte black plastic tray",
    "black rubber desk mat", "dark gray felt desk pad", "gray textured plastic board", "black acrylic board",
    "dark gray laminate shelf", "anthracite brushed metal surface", "white laminate desk", "light wood desk",
]
DETAILS = [
    "clean", "with faint dust specks", "with fine scratches", "with dried water stains", "with fingerprints and smudges",
    "with a faint glare reflection", "with subtle scuff marks", "slightly worn", "with a soft shadow falling across one side",
]
LIGHTS = ["soft overhead indoor light", "warm indoor lamp light", "cool fluorescent office light", "uneven lighting, brighter on one side",
          "dim indoor light"]
NEG = "objects, items, things, hands, person, text, logo, watermark, border, frame, tray edge, wall, drawing"


def main():
    n = int(sys.argv[1])
    from diffusers import Lumina2Pipeline
    pipe = Lumina2Pipeline.from_pretrained("Alpha-VLLM/Lumina-Image-2.0", torch_dtype=torch.bfloat16).to("cuda")
    pipe.set_progress_bar_config(disable=True)
    OUT.mkdir(parents=True, exist_ok=True)
    rng = np.random.default_rng(7)
    log = open(OUT / "backgrounds.jsonl", "a")
    t0 = time.time()
    for i in range(n):
        name = f"gen_{i:04d}.jpg"
        s, d, l = rng.choice(SURFACES), rng.choice(DETAILS), rng.choice(LIGHTS)
        if (OUT / name).exists():
            continue
        p = (f"Top-down overhead photo of an empty {s} surface {d}, {l}, the surface fills the entire frame edge to edge, "
             f"nothing on it, realistic photo taken with a small camera module, slight sensor noise")
        img = pipe(prompt=p, negative_prompt=NEG, guidance_scale=4.0, num_inference_steps=30, width=1024, height=576,
                   generator=torch.Generator("cpu").manual_seed(1000 + i)).images[0]
        img.save(OUT / name, quality=92)
        log.write(json.dumps({"file": name, "surface": str(s), "detail": str(d), "light": str(l), "prompt": p}) + "\n")
        log.flush()
        if (i + 1) % 20 == 0:
            print(f"{i + 1}/{n} · {(time.time() - t0) / (i + 1):.1f} s/장", flush=True)


if __name__ == "__main__":
    main()
