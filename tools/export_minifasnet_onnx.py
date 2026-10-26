# MiniFASNet pth -> onnx
# usage: python export_minifasnet_onnx.py <Silent-Face-Anti-Spoofing 경로> <출력 폴더>

import sys
import os
import torch

repo, out = sys.argv[1], sys.argv[2]
sys.path.insert(0, repo)

from src.model_lib.MiniFASNet import MiniFASNetV2, MiniFASNetV1SE
from src.utility import get_kernel

models = {
    "2.7_80x80_MiniFASNetV2.pth": (MiniFASNetV2, "anti_spoofing_minifasnetv2_2.7_80x80.onnx"),
    "4_0_0_80x80_MiniFASNetV1SE.pth": (MiniFASNetV1SE, "anti_spoofing_minifasnetv1se_4.0_80x80.onnx"),
}

os.makedirs(out, exist_ok=True)

for pth, (net, name) in models.items():
    model = net(conv6_kernel=get_kernel(80, 80))
    state = torch.load(os.path.join(repo, "resources/anti_spoof_models", pth), map_location="cpu")
    state = {k.replace("module.", "", 1): v for k, v in state.items()}
    model.load_state_dict(state)
    model.eval()

    dummy = torch.rand(1, 3, 80, 80)
    torch.onnx.export(model, dummy, os.path.join(out, name),
                      input_names=["input"], output_names=["logits"],
                      opset_version=11, dynamo=False)
    print("saved", name)
