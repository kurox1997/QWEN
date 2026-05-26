#!/bin/bash
set -e
echo "=== Qwen-Rapid-AIO Serverless v8 (OOM対策版) ==="

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

# PyTorch メモリ断片化軽減 (ComfyUI OOM ログの公式推奨)
export PYTORCH_ALLOC_CONF=expandable_segments:True
echo "PYTORCH_ALLOC_CONF=expandable_segments:True (fragmentation mitigation)"

# SageAttention 動作確認
python3 -c "from sageattention import sageattn_qk_int8_pv_fp16_cuda; print('SageAttention 2.x ready')" \
  || echo "WARNING: SageAttention 2.x not available"

# ComfyUI 起動
# 重要な変更:
#   - --highvram 削除 (Qwen 21GB + Text Encoder で OOM になるため)
#   - --disable-smart-memory 削除 (スマートメモリでオフロード必要)
#   - --fast のみ残す (FP16高速モード)
#   - SageAttention は KJNodes Patch Sage Attention ノード経由で適用 (KSampler時のみ)
echo "worker-comfyui: Starting ComfyUI (--fast only, smart VRAM management enabled)"
python3 -u /comfyui/main.py \
  --disable-auto-launch \
  --disable-metadata \
  --fast &

echo "worker-comfyui: Starting RunPod Handler"
exec python3 -u /handler.py