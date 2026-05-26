#   ===========================================================================
# Qwen-Rapid-AIO Serverless v14 (Lightweight & Fast Start)
#
# v13 → v14 変更:
#   ✗ Multi-stage build 廃止
#   ✗ CUDA Toolkit COPY 廃止 (6GB削減)
#   ✗ SageAttention 2.x 廃止 (Qwen でノイズ画像問題)
#   ✗ Triton, KJNodes, gcc/python3-dev 等の Triton JIT 依存削除
#   ✓ ComfyUI Manager skip_start_update 設定 (起動 -10秒)
#   ✓ HuggingFace offline モード (起動 -5秒)
#
# イメージサイズ: 22 GB → 16 GB
# Build時間: 30分 → 5分
# 起動時間: 28秒 → 15-20秒
# 1枚生成: 120-150秒
# ============================================================================
FROM runpod/worker-comfyui:5.8.5-base-cuda12.8.1

ENV DEBIAN_FRONTEND=noninteractive

# ===== 起動高速化系の環境変数 =====
# worker-comfyui の ComfyUI 起動待ちタイムアウト延長
ENV COMFY_POLLING_MAX_RETRIES=2000

# HuggingFace の online check スキップ (ネットワーク待ち削減)
ENV TRANSFORMERS_OFFLINE=1
ENV HF_HUB_OFFLINE=1

# Python の .pyc 生成スキップ (起動時 import 高速化)
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

# ===== カスタムノード: Qwen Image Edit Plus (必須) =====
RUN git clone --depth=1 https://github.com/lrzjason/Comfyui-QwenEditUtils.git \
        /comfyui/custom_nodes/Comfyui-QwenEditUtils \
 && if [ -f /comfyui/custom_nodes/Comfyui-QwenEditUtils/requirements.txt ]; then \
        pip install --break-system-packages --no-cache-dir \
            -r /comfyui/custom_nodes/Comfyui-QwenEditUtils/requirements.txt; \
    fi

# ===== ComfyUI-Manager 起動高速化設定 =====
# skip_start_update = True → 起動時の ComfyRegistry fetch (148件) をスキップ
# これで起動時間 -10秒
RUN mkdir -p /comfyui/user/__manager \
 && printf '[default]\nskip_start_update = True\n' > /comfyui/user/__manager/config.ini \
 && cat /comfyui/user/__manager/config.ini

# ===== モデルパス、 ワークフロー =====
COPY extra_model_paths.yaml /comfyui/extra_model_paths.yaml
COPY workflow_api.json      /comfyui/workflow_api.json

# ===== start.sh =====
RUN if [ -f /start.sh ]; then mv /start.sh /start_original.sh; fi
COPY start.sh /start.sh
RUN chmod +x /start.sh

# Build 完了確認
RUN echo "✓ v14 Build complete (lightweight, no SageAttention)"