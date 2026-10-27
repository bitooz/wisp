#!/bin/bash
# The machine, alongside setup.sh: Microsoft TRELLIS.2 (4B) in its own conda env (torch 2.6, cu124), its
# CUDA extensions built for this card only, and its weights. Two of the models it asks for are gated on
# Hugging Face, so trellis.py loads open copies of the same weights instead (DINOv3 ViT-L/16 from a
# mirror; BiRefNet for the cut-out, which isn't used, since it gets the same cut-out as Hunyuan's).
set -x
cd ~/job
source /opt/conda/etc/profile.d/conda.sh
conda create -y -q -n t2 python=3.10 > t2-conda.log 2>&1
conda activate t2
pip install -q torch==2.6.0 torchvision==0.21.0 --index-url https://download.pytorch.org/whl/cu124
pip install -q "huggingface_hub[cli]<1" hf_transfer
get() {
  huggingface-cli download microsoft/TRELLIS.2-4B --local-dir ~/T2W &&
  huggingface-cli download microsoft/TRELLIS-image-large --include "ckpts/ss_dec_conv3d_16l8_fp16.*" &&
  huggingface-cli download camenduru/dinov3-vitl16-pretrain-lvd1689m &&
  huggingface-cli download ZhengPeng7/BiRefNet
}
(for i in 1 2 3; do (export HF_HUB_ENABLE_HF_TRANSFER=$([ $i = 1 ] && echo 1 || echo 0); get) && echo T2_MODELS_OK && break; done) > t2-models.log 2>&1 &
for i in 1 2 3; do git clone -q --depth 1 --recursive https://github.com/microsoft/TRELLIS.2 ~/T2 && break; rm -rf ~/T2; done
pip install -q imageio imageio-ffmpeg tqdm easydict opencv-python-headless ninja trimesh "transformers==4.57.1" kornia timm einops zstandard lpips pandas safetensors
pip install -q git+https://github.com/EasternJournalist/utils3d.git@9a4eb15e4021b67b12c460c7057d642626897ec8
pip install -q https://github.com/Dao-AILab/flash-attention/releases/download/v2.7.3/flash_attn-2.7.3+cu12torch2.6cxx11abiFALSE-cp310-cp310-linux_x86_64.whl || pip install -q xformers==0.0.29.post2
export TORCH_CUDA_ARCH_LIST=$(python -c "import torch; c=torch.cuda.get_device_capability(); print(f'{c[0]}.{c[1]}')")
export MAX_JOBS=$(nproc)
mkdir -p /tmp/ext && cd /tmp/ext
git clone -q -b v0.4.0 https://github.com/NVlabs/nvdiffrast.git && pip install -q ./nvdiffrast --no-build-isolation
git clone -q -b renderutils https://github.com/JeffreyXiang/nvdiffrec.git && pip install -q ./nvdiffrec --no-build-isolation
git clone -q --recursive https://github.com/JeffreyXiang/CuMesh.git && pip install -q ./CuMesh --no-build-isolation
git clone -q --recursive https://github.com/JeffreyXiang/FlexGEMM.git && pip install -q ./FlexGEMM --no-build-isolation
cp -r ~/T2/o-voxel ./o-voxel && pip install -q ./o-voxel --no-build-isolation
python -c "import torch, o_voxel, cumesh, flex_gemm, nvdiffrast.torch; print('T2_EXT_OK', torch.cuda.get_device_name())"
wait
# The gated models' open copies
python - <<'EOF'
import json, os
p = os.path.expanduser('~/T2W/pipeline.json')
d = json.load(open(p))
d['args']['image_cond_model']['args']['model_name'] = 'camenduru/dinov3-vitl16-pretrain-lvd1689m'
d['args']['rembg_model']['args']['model_name'] = 'ZhengPeng7/BiRefNet'
json.dump(d, open(p, 'w'), indent=1)
EOF
echo T2_SETUP_DONE
