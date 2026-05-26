# ============================================================================
# Qwen-Rapid-AIO Serverless v6 - Plan B (Ubuntu 24.04 標準 Python 3.12)
#
# 変更点: deadsnakes PPA 不要、 distutils 問題なし
# Ubuntu 24.04 は Python 3.12.3 標準 → worker-comfyui の Python 3.12.3 と完全一致
# 期待効果: RTX 4090 で 60-90 秒/枚
# ============================================================================

# =============================================================================
# Stage 1: SageAttention 2.x wheel ビルダー
# Ubuntu 24.04 + CUDA 12.8.1 devel + Python 3.12 標準
# =============================================================================
FROM nvidia/cuda:12.8.1-cudnn-devel-ubuntu24.04 AS sage-builder

ENV DEBIAN_FRONTEND=noninteractive

# Python 3.12 + ビルドツール (Ubuntu 24.04 標準で全て 3.12 系)
RUN apt-get update && apt-get install -y --no-install-recommends \
        python3 python3-dev python3-pip python3-venv \
        git build-essential ninja-build curl ca-certificates \
 && rm -rf /var/lib/apt/lists/*

# 環境確認 (早期失敗検出)
RUN nvcc --version && python3 --version && python3 -m pip --version

# main stage と同じ torch を入れる (ABI互換のため必須)
RUN python3 -m pip install --break-system-packages --no-cache-dir \
        torch==2.10.0 \
        --index-url https://download.pytorch.org/whl/cu128

# setuptools 旧版 (SageAttention 公式推奨) + ビルド依存
RUN python3 -m pip install --break-system-packages --no-cache-dir \
        "setuptools<=75.8.2" wheel packaging ninja

# SageAttention 2.x を wheel としてビルド
RUN git clone --depth=1 https://github.com/thu-ml/SageAttention.git /tmp/SageAttention \
 && cd /tmp/SageAttention \
 && MAX_JOBS=4 EXT_PARALLEL=4 NVCC_APPEND_FLAGS="--threads 8" \
    python3 setup.py bdist_wheel \
 && ls -la dist/ \
 && echo "=== Built SageAttention wheel ==="

# =============================================================================
# Stage 2: メインの worker-comfyui イメージ
# =============================================================================
FROM runpod/worker-comfyui:5.8.5-base-cuda12.8.1

# ----- Step 1: Triton 最新版 -----
RUN pip install --break-system-packages --no-cache-dir -U triton

# ----- Step 2: ビルドした SageAttention wheel をコピー & インストール -----
COPY --from=sage-builder /tmp/SageAttention/dist/*.whl /tmp/
RUN ls /tmp/*.whl \
 && pip install --break-system-packages --no-cache-dir /tmp/sageattention*.whl \
 && rm /tmp/sageattention*.whl \
 && python3 -c "from sageattention import sageattn_qk_int8_pv_fp16_cuda; print('SageAttention 2.x OK')"

# ----- Step 3: ComfyUI-KJNodes (Patch Sage Attention ノード提供) -----
RUN git clone --depth=1 https://github.com/kijai/ComfyUI-KJNodes.git \
        /comfyui/custom_nodes/ComfyUI-KJNodes \
 && if [ -f /comfyui/custom_nodes/ComfyUI-KJNodes/requirements.txt ]; then \
        pip install --break-system-packages --no-cache-dir \
            -r /comfyui/custom_nodes/ComfyUI-KJNodes/requirements.txt; \
    fi

# ----- Step 4: Comfyui-QwenEditUtils -----
RUN git clone --depth=1 https://github.com/lrzjason/Comfyui-QwenEditUtils.git \
        /comfyui/custom_nodes/Comfyui-QwenEditUtils \
 && if [ -f /comfyui/custom_nodes/Comfyui-QwenEditUtils/requirements.txt ]; then \
        pip install --break-system-packages --no-cache-dir \
            -r /comfyui/custom_nodes/Comfyui-QwenEditUtils/requirements.txt; \
    fi

# ----- Step 5: モデルパス、ワークフロー、起動スクリプト -----
COPY extra_model_paths.yaml /comfyui/extra_model_paths.yaml
COPY workflow_api.json      /comfyui/workflow_api.json

# ----- Step 6: start.sh -----
RUN if [ -f /start.sh ]; then mv /start.sh /start_original.sh; fi
COPY start.sh /start.sh
RUN chmod +x /start.sh