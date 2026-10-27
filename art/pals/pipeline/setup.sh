#!/bin/bash
# The machine (the pytorch/pytorch:2.5.1-cuda12.4-cudnn9-devel image): Hunyuan3D-2.1's shape and PBR
# paint models with their compiled renderer. The weights come down while the rest installs. (The rig
# runs on the Mac, with Blender as a Python module.)
set -x
cd ~/job
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq && apt-get install -y -qq git wget xz-utils libgl1 libglib2.0-0 libxrender1 libxi6 libxkbcommon0 libsm6 libxext6 libxxf86vm1 libxfixes3 > apt.log 2>&1
pip install -q "huggingface_hub[cli]==0.30.2" hf_transfer
# (hf_transfer and HTTP/2 have both dropped downloads on some hosts: hf_transfer first, then plain retries)
git config --global http.version HTTP/1.1
get() { huggingface-cli download tencent/Hunyuan3D-2.1 && huggingface-cli download facebook/dinov2-giant --include "*.json" "model.safetensors"; }
(for i in 1 2 3; do (export HF_HUB_ENABLE_HF_TRANSFER=$([ $i = 1 ] && echo 1 || echo 0); get) && echo MODELS_OK && break; done) > models.log 2>&1 &
for i in 1 2 3; do git clone --depth 1 https://github.com/Tencent-Hunyuan/Hunyuan3D-2.1 ~/H21 && break; rm -rf ~/H21; done
cd ~/H21
grep -v -E '^(--extra-index-url|bpy|gradio|fastapi|uvicorn|deepspeed|pythreejs|tb_nightly)' requirements.txt > req.txt
pip install -q -r req.txt
# basicsr still imports a module torchvision dropped.
sed -i "s/torchvision.transforms.functional_tensor/torchvision.transforms.functional/" $(python -c "import importlib.util; print(importlib.util.find_spec('basicsr').submodule_search_locations[0])")/data/degradations.py
export TORCH_CUDA_ARCH_LIST="8.0;8.6;8.9"
(cd hy3dpaint/custom_rasterizer && pip install --no-build-isolation -e .)
(cd hy3dpaint/DifferentiableRenderer && bash compile_mesh_painter.sh)
mkdir -p hy3dpaint/ckpt ckpt
wget -q https://github.com/xinntao/Real-ESRGAN/releases/download/v0.1.0/RealESRGAN_x4plus.pth -P hy3dpaint/ckpt && cp hy3dpaint/ckpt/RealESRGAN_x4plus.pth ckpt/
python -c "import torch, custom_rasterizer; print('RAST_OK', torch.cuda.get_device_name())"
wait
echo SETUP_DONE
