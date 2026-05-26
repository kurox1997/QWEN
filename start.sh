#!/bin/bash
set -e
echo "=== Qwen-Rapid-AIO Serverless v10 (Plan B-5: Full SageAttention 2.x) ==="

# Network Volume を /workspace としても参照できるようにする
if [ -d /runpod-volume ] && [ ! -e /workspace ]; then
  ln -s /runpod-volume /workspace
  echo "Linked /runpod-volume -> /workspace"
fi

# tcmalloc (メモリ管理改善)
TCMALLOC="$(ldconfig -p | grep -Po 'libtcmalloc.so.\d' | head -n 1)"
if [ -n "$TCMALLOC" ]; then
  export LD_PRELOAD="${TCMALLOC}"
fi

# PyTorch メモリ断片化軽減
export PYTORCH_ALLOC_CONF=expandable_segments:True

# Triton JIT 用環境変数 (Dockerfileで設定済みだが念のため)
export CC=${CC:-gcc}
export CXX=${CXX:-g++}
export CUDA_HOME=${CUDA_HOME:-/usr/local/cuda}
export PATH="/usr/local/cuda/bin:${PATH}"
export LD_LIBRARY_PATH="/usr/local/cuda/lib64:${LD_LIBRARY_PATH:-}"

# 環境確認
echo "--- Runtime environment check ---"
which nvcc && nvcc --version | tail -1 || echo "WARNING: nvcc not found"
which gcc && gcc --version | head -1 || echo "WARNING: gcc not found"

# SageAttention 動作確認
python3 -c "from sageattention import sageattn_qk_int8_pv_fp16_cuda; print('SageAttention 2.x ready')" \
  || echo "WARNING: SageAttention 2.x not available"

# ComfyUI 起動
# --highvram / --disable-smart-memory は使わない (OOM回避)
# SageAttention は KJNodes Patch Sage Attention ノード経由で適用
echo "worker-comfyui: Starting ComfyUI (--fast only, smart VRAM management)"
python3 -u /comfyui/main.py \
  --disable-auto-launch \
  --disable-metadata \
  --fast &

echo "worker-comfyui: Starting RunPod Handler"
exec python3 -u /handler.py