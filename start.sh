#!/bin/bash
set -e
echo "=== Qwen-Rapid-AIO Serverless v15 (No --fast, Clean Default) ==="

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

# PyTorch メモリ断片化軽減 (OOM予防)
export PYTORCH_ALLOC_CONF=expandable_segments:True

# 環境表示
echo "ENV: COMFY_POLLING_MAX_RETRIES=${COMFY_POLLING_MAX_RETRIES}"
echo "ENV: PYTORCH_ALLOC_CONF=${PYTORCH_ALLOC_CONF}"

# ComfyUI 起動
# 重要な変更:
#   ✗ --fast 削除 (fp8 モデル × fp16 accumulation でノイズ画像の原因確定)
#   ✗ --highvram / --disable-smart-memory なし (smart memoryで動的VRAM管理)
#   ✓ ComfyUI デフォルト動作 = fp8 を bf16 manual cast で安全展開
#   ✓ pytorch attention (Qwen安全、 SDPA で内部最適化済み)
echo "worker-comfyui: Starting ComfyUI (clean default, no aggressive flags)"
python3 -u /comfyui/main.py \
  --disable-auto-launch \
  --disable-metadata &

echo "worker-comfyui: Starting RunPod Handler"
exec python3 -u /handler.py