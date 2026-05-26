# ============================================================================
# Qwen-Rapid-AIO Serverless（RTX 4090向け 最高速構成 v3）
#
# 構成方針:
#   1) SageAttention 2.x をソースビルド (Qwen 黒画像問題を回避)
#   2) ComfyUI-KJNodes で Patch Sage Attention ノード提供
#   3) --use-sage-attention フラグは絶対に使わない (公式 Discussion #11583)
#   4) workflow_api.json に PathchSageAttentionKJ を挿入済み
#   5) --fast --highvram --disable-smart-memory で VRAM オフロード回避
#
# 期待効果: RTX 4090 で 60-90 秒/枚 (現状 184 秒 → 約 2-3 倍速)
# ============================================================================
FROM runpod/worker-comfyui:5.8.5-base-cuda12.8.1

# ----- Step 1: Triton 最新版 (SageAttention 2.x の依存) -----
RUN pip install --break-system-packages --no-cache-dir -U triton

# ----- Step 2: SageAttention 2.x をソースビルド (10-15分のビルド時間) -----
# 公式推奨手順 (https://github.com/thu-ml/SageAttention)
# setuptools の旧版固定が必要 (>75.8.2 ではビルド失敗の既知バグあり)
RUN pip install --break-system-packages --no-cache-dir "setuptools<=75.8.2" --force-reinstall \
 && git clone --depth=1 https://github.com/thu-ml/SageAttention.git /tmp/SageAttention \
 && cd /tmp/SageAttention \
 && EXT_PARALLEL=4 NVCC_APPEND_FLAGS="--threads 8" MAX_JOBS=4 \
    pip install --break-system-packages --no-cache-dir --no-build-isolation . \
 && rm -rf /tmp/SageAttention \
 && python3 -c "from sageattention import sageattn_qk_int8_pv_fp16_cuda; print('SageAttention 2.x OK')"

# ----- Step 3: ComfyUI-KJNodes (Patch Sage Attention ノード提供) -----
RUN git clone --depth=1 https://github.com/kijai/ComfyUI-KJNodes.git \
        /comfyui/custom_nodes/ComfyUI-KJNodes \
 && if [ -f /comfyui/custom_nodes/ComfyUI-KJNodes/requirements.txt ]; then \
        pip install --break-system-packages --no-cache-dir \
            -r /comfyui/custom_nodes/ComfyUI-KJNodes/requirements.txt; \
    fi

# ----- Step 4: Qwen Image Edit Plus 用 カスタムノード -----
RUN git clone --depth=1 https://github.com/lrzjason/Comfyui-QwenEditUtils.git \
        /comfyui/custom_nodes/Comfyui-QwenEditUtils \
 && if [ -f /comfyui/custom_nodes/Comfyui-QwenEditUtils/requirements.txt ]; then \
        pip install --break-system-packages --no-cache-dir \
            -r /comfyui/custom_nodes/Comfyui-QwenEditUtils/requirements.txt; \
    fi

# ----- Step 5: モデルパス -----
COPY extra_model_paths.yaml /comfyui/extra_model_paths.yaml
COPY workflow_api.json      /comfyui/workflow_api.json

# ----- Step 6: start.sh 完全書き換え -----
# 重要: --use-sage-attention フラグは絶対に使わない
#       (Qwen で黒画像 NaN 確定: ComfyUI Discussion #11583)
RUN if [ -f /start.sh ]; then mv /start.sh /start_original.sh; fi \
 && cat > /start.sh <<'STARTSH'
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
STARTSH
RUN chmod +x /start.sh
