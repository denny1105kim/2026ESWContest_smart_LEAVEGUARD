# ORBIT ProtoNets EfficientNet-B0 특징 추출기 -> onnx. 입력 224x224 RGB (ImageNet 정규화), 출력 1280차원 (GAP, 정규화 안 함)
#
# 체크포인트는 ORBIT 레포의 git 기록에만 남아 있다 (README 다운로드 주소는 끊김).
#   git clone --filter=blob:none --no-checkout https://github.com/microsoft/ORBIT-Dataset orbit
#   cd orbit
#   git show 5a2b4e8:checkpoints/orbit_cluve_protonets_efficientnetb0_224_lite.pth > protonets_effb0.pth
#   mkdir code && git archive 5a2b4e8 features feature_adapters models | tar -x -C code
#
# usage: python export_orbit_onnx.py <code 폴더> <체크포인트.pth> <출력 폴더>
import os
import sys
import types

import torch

code, ckpt, out = sys.argv[1], sys.argv[2], sys.argv[3]
os.makedirs(out, exist_ok=True)

# features/__init__.py 가 학습 코드 전체를 끌어오므로 빈 패키지로 대신하고, 추론에 필요 없는 thop 은 가짜 모듈로 막는다
sys.path.insert(0, code)
for pkg in ("features", "feature_adapters", "models"):
    module = types.ModuleType(pkg)
    module.__path__ = [os.path.join(code, pkg)]
    sys.modules[pkg] = module
thop = types.ModuleType("thop.vision.basic_hooks")
thop.count_convNd = thop.zero_ops = None
sys.modules.update({"thop": types.ModuleType("thop"), "thop.vision": types.ModuleType("thop.vision"), "thop.vision.basic_hooks": thop})
from features.efficientnet import efficientnetb0  # noqa: E402

model = efficientnetb0(pretrained=False)
state = torch.load(ckpt, map_location="cpu", weights_only=True)
state = {k[len("feature_extractor."):]: v for k, v in state.items() if k.startswith("feature_extractor.")}
missing, unexpected = model.load_state_dict(state, strict=False)
# 분류층(_fc)은 ProtoNets 가 쓰지 않는다
assert set(missing) <= {"_fc.weight", "_fc.bias"} and not unexpected, (missing, unexpected)
model.eval()
model.set_swish(memory_efficient=False)   # 학습용 swish 는 onnx 로 못 내보낸다

dummy = torch.rand(1, 3, 224, 224)
path = os.path.join(out, "orbit_protonets_effb0_224.onnx")
torch.onnx.export(model, dummy, path, input_names=["input"], output_names=["embedding"], opset_version=13, dynamo=False)

try:
    import numpy as np
    import onnxruntime as ort
    with torch.no_grad():
        ref = model(dummy).numpy()
    got = ort.InferenceSession(path).run(None, {"input": dummy.numpy()})[0]
    print("PyTorch <-> onnxruntime 최대 차이", float(np.abs(got - ref).max()))
except ImportError:
    pass
print("saved", path)
