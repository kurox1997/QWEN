#!/bin/bash
set -e
echo "=== Qwen-Rapid-AIO Serverless v14 (Lightweight & Fast Start) ==="

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

# PyTorch メモリ断片化軽減 (OOM対策)
export PYTORCH_ALLOC_CONF=expandable_segments:True

# 環境表示 (確認用)
echo "ENV: COMFY_POLLING_MAX_RETRIES=${COMFY_POLLING_MAX_RETRIES}"
echo "ENV: TRANSFORMERS_OFFLINE=${TRANSFORMERS_OFFLINE}"
echo "ENV: PYTORCH_ALLOC_CONF=${PYTORCH_ALLOC_CONF}"

# ComfyUI 起動
# --fast: FP16 accumulation (10-20%高速化)
# (SageAttention は使わない、 Qwen Image でノイズ問題のため)
echo "worker-comfyui: Starting ComfyUI (--fast, pytorch SDPA attention)"
python3 -u /comfyui/main.py \
  --disable-auto-launch \
  --disable-metadata \
  --fast &

echo "worker-comfyui: Starting RunPod Handler"
exec python3 -u /handler.py