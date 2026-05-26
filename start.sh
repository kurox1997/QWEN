#!/bin/bash
set -e
echo "=== Qwen-Rapid-AIO Serverless v3 (SageAttention 2.x + KJNodes Patch) ==="

# Network Volume を /workspace としても参照できるようにする
if [ -d /runpod-volume ] && [ ! -e /workspace ]; then
  ln -s /runpod-volume /workspace
  echo "Linked /runpod-volume -> /workspace"
fi

# tcmalloc (メモリ管理改善)
TCMALLOC="$(ldconfig -p | grep -Po 'libtcmalloc.so.\d' | head -n 1)"
if [ -n "$TCMALLOC" ]; then
  export LD_PRELOAD="${TCMALLOC}"
  echo "Using ${TCMALLOC} for memory management"
fi

# SageAttention 動作確認 (起動失敗を早期検出)
python3 -c "from sageattention import sageattn_qk_int8_pv_fp16_cuda; print('SageAttention 2.x ready')" \
  || echo "WARNING: SageAttention 2.x not available, Patch node will fail"

# ComfyUI 起動
# 注: --use-sage-attention は使わない (Qwen 黒画像問題回避)
#     KJNodes Patch Sage Attention ノードで安全に有効化する設計
echo "worker-comfyui: Starting ComfyUI (--fast --highvram --disable-smart-memory)"
python3 -u /comfyui/main.py \
  --disable-auto-launch \
  --disable-metadata \
  --fast \
  --highvram \
  --disable-smart-memory &

echo "worker-comfyui: Starting RunPod Handler"
exec python3 -u /handler.py
