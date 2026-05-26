#!/bin/bash
set -e
echo "=== Qwen-Rapid-AIO Serverless v12 (Plan B-5: Full Triton JIT Stack) ==="

# Network Volume を /workspace としても参照できるようにする
if [ -d /runpod-volume ] && [ ! -e /workspace ]; then
  ln -s /runpod-volume /workspace
  echo "Linked /runpod-volume -> /workspace"
fi

# tcmalloc
TCMALLOC="$(ldconfig -p | grep -Po 'libtcmalloc.so.\d' | head -n 1)"
if [ -n "$TCMALLOC" ]; then export LD_PRELOAD="${TCMALLOC}"; fi

# PyTorch メモリ断片化軽減
export PYTORCH_ALLOC_CONF=expandable_segments:True

# Triton JIT 必須環境変数
export CC=${CC:-gcc}
export CXX=${CXX:-g++}
export CUDA_HOME=${CUDA_HOME:-/usr/local/cuda}
export PATH="/usr/local/cuda/bin:${PATH}"
export LD_LIBRARY_PATH="/usr/local/cuda/lib64:${LD_LIBRARY_PATH:-}"

# === Runtime 依存 チェック (起動時にひと目で確認) ===
echo "--- Triton JIT runtime check ---"
which gcc && gcc --version | head -1
which nvcc && nvcc --version | tail -1
[ -f /usr/include/python3.12/Python.h ] && echo "✓ Python.h found" || echo "✗ MISSING Python.h"
ldconfig -p | grep -q libcuda.so && echo "✓ libcuda.so available" || echo "⚠ libcuda.so check (RunPod runtime mount expected)"

# Triton & SageAttention import チェック
python3 -c "import triton; print('✓ Triton', triton.__version__)" || echo "✗ Triton import failed"
python3 -c "from sageattention import sageattn_qk_int8_pv_fp16_cuda; print('✓ SageAttention 2.x ready')" || echo "✗ SageAttention not available"
echo "--- check complete ---"

# ComfyUI 起動
echo "worker-comfyui: Starting ComfyUI (--fast only)"
python3 -u /comfyui/main.py \
  --disable-auto-launch \
  --disable-metadata \
  --fast &

echo "worker-comfyui: Starting RunPod Handler"
exec python3 -u /handler.py