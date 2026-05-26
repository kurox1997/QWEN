# syntax=docker/dockerfile:1.7
# === Qwen-Rapid-AIO Serverless Worker ===
# ベース：公式 worker-comfyui 5.8.5 / CUDA 12.8.1（cu128環境に整合）
FROM runpod/worker-comfyui:5.8.5-base-cuda12.8.1

# ===== 高速化最適化追加 =====
# SageAttention（35-40%短縮、DaSiWa Batch実績あり）
RUN pip install --break-system-packages --no-cache-dir sageattention

# Triton 最新版
RUN pip install --break-system-packages --no-cache-dir -U triton

# ComfyUI 起動オプション
ENV COMFY_ARGS="--use-sage-attention --fast --highvram --disable-smart-memory"

# === カスタムノード：Comfyui-QwenEditUtils ===
RUN git clone --depth=1 https://github.com/lrzjason/Comfyui-QwenEditUtils.git \
      /comfyui/custom_nodes/Comfyui-QwenEditUtils \
 && if [ -f /comfyui/custom_nodes/Comfyui-QwenEditUtils/requirements.txt ]; then \
      pip install --no-cache-dir -r /comfyui/custom_nodes/Comfyui-QwenEditUtils/requirements.txt; \
    fi

# === 必須ファイルのコピー ===
COPY extra_model_paths.yaml /comfyui/extra_model_paths.yaml
COPY workflow_api.json      /comfyui/workflow_api.json

# === 起動スクリプトのラップ ===
# 元の /start.sh を /start_original.sh に退避し、
# その手前で /workspace シンボリックリンク作成だけを行う薄いラッパを置く。
# （元 Dockerfile の致命的バグ＝自分自身を exec する無限再帰を解消）
RUN if [ -f /start.sh ]; then mv /start.sh /start_original.sh; fi \
 && printf '%s\n' \
      '#!/bin/bash' \
      'set -e' \
      'echo "=== Qwen-Rapid-AIO Serverless Starting ==="' \
      '' \
      '# Network Volume を /workspace としても参照できるようにする' \
      'if [ -d /runpod-volume ] && [ ! -e /workspace ]; then' \
      '  ln -s /runpod-volume /workspace' \
      '  echo "Linked /runpod-volume -> /workspace"' \
      'fi' \
      '' \
      '# 元の RunPod 起動スクリプトに制御を渡す' \
      'exec /start_original.sh "$@"' \
    > /start.sh \
 && chmod +x /start.sh

# 公式イメージの ENTRYPOINT を上書きしないため CMD のみ指定
CMD ["/start.sh"]