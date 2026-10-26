# DINOv2-S reg (ViT-S/14 + register 4개) -> onnx. 입력 NxN(기본 168, 14의 배수), 출력 384차원 특징
# usage: python export_dinov2_onnx.py <출력 폴더> [크기]
import sys
import os
import torch

out = sys.argv[1]
size = int(sys.argv[2]) if len(sys.argv) > 2 else 168
name = f"dinov2_vits14_reg_{size}.onnx"
os.makedirs(out, exist_ok=True)

model = torch.hub.load("facebookresearch/dinov2", "dinov2_vits14_reg").eval()

# 입력 크기에 맞춘 위치 임베딩을 미리 계산해 고정 (실행 중 bicubic 보간 제거)
with torch.no_grad():
    pos = model.interpolate_pos_encoding(torch.zeros(1, 1 + (size // 14) ** 2, 384), size, size)
model.interpolate_pos_encoding = lambda x, w, h: pos

# 입력을 이미지 하나로 고정 (그대로 내보내면 쓰지 않는 masks 입력이 딸려 나온다)
class Embed(torch.nn.Module):
    def __init__(self, m):
        super().__init__()
        self.m = m

    def forward(self, x):
        return self.m(x)


dummy = torch.rand(1, 3, size, size)
torch.onnx.export(Embed(model), dummy, os.path.join(out, name),
                  input_names=["input"], output_names=["embedding"],
                  opset_version=17, dynamo=False)
print("saved", name)
